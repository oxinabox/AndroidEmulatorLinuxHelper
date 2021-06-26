#! /usr/local/bin/julia-1.7
const EMULATOR = "Android Emulator"
const AVD_DIR = expanduser("~/.android/avd/oxphone.avd/")
const ADB = expanduser("~/Android/Sdk/platform-tools/adb")

abstract type Rotation end
struct Normal <: Rotation end
struct Left <: Rotation end
struct Right <: Rotation end
struct Inverted <: Rotation end

abstract type Orientation end
struct Portrait <: Orientation end
struct Landscape <: Orientation end

abstract type Turn end
struct Clockwise <: Turn end
struct CounterClockwise <: Turn end
struct Flip <: Turn end
struct NoTurn <: Turn end

abstract type Viewable{N <: Orientation} end
struct RealScreen <: Viewable{Landscape} end
struct AndroidWindow <: Viewable{Portrait} end
struct AndroidView <: Viewable{Portrait} end

struct Emulator <: Viewable{Landscape} end

rotate(::Normal, ::Clockwise) = Right()
rotate(::Right, ::Clockwise) = Inverted()
rotate(::Inverted, ::Clockwise) = Left()
rotate(::Left, ::Clockwise) = Normal()
rotate(::Normal, ::CounterClockwise) = Left()
rotate(::Right, ::CounterClockwise) = Normal()
rotate(::Inverted, ::CounterClockwise) = Right()
rotate(::Left, ::CounterClockwise) = Inverted()
rotate(::Normal, ::Flip) = Inverted()
rotate(::Right, ::Flip) = Left()
rotate(::Inverted, ::Flip) = Normal()
rotate(::Left, ::Flip) = Right()
rotate(x, ::NoTurn) = x

needed_turn(::T, ::T) where T = NoTurn()
needed_turn(::Normal, ::Inverted) = Flip()
needed_turn(::Inverted, ::Normal) = Flip()
needed_turn(::Left, ::Right) = Flip()
needed_turn(::Right, ::Left) = Flip()
needed_turn(::Inverted, ::Left) = Clockwise() 
needed_turn(::Inverted, ::Right) = CounterClockwise()
needed_turn(::Normal, ::Left) = CounterClockwise() 
needed_turn(::Normal, ::Right) = Clockwise()
needed_turn(::Right, ::Inverted) = Clockwise()
needed_turn(::Right, ::Normal) = CounterClockwise()
needed_turn(::Left, ::Normal) = Clockwise()
needed_turn(::Left, ::Inverted) = CounterClockwise()

#==
using Test
@testset "turn/rotate logic" begin
    for r1 in (Normal(), Inverted(), Left(), Right())
        for r2 in (Normal(), Inverted(), Left(), Right())
            t = needed_turn(r1, r2)
            @test rotate(r1, t) == r2
        end
    end
end
==#

orientation(::Viewable{Landscape}, ::Union{Normal,Inverted}) = Landscape()
orientation(::Viewable{Landscape}, ::Union{Left,Right}) = Portrait()
orientation(::Viewable{Portrait}, ::Union{Normal,Inverted}) = Portrait()
orientation(::Viewable{Portrait}, ::Union{Left,Right}) = Landscape()
orientation(x) = orientation(x, rotation(x))

### RealScreen

function rotation(::RealScreen)::Rotation
    display_details = readlines(`xrandr -q`)[2]
    rot_str = replace(split(display_details, " ")[5], "("=>"")
    return if rot_str == "normal"
        Normal()
    elseif rot_str == "left"
        Left()
    elseif rot_str == "right"
        Right()
    elseif rot_str == "inverted"
        Inverted()
    else
        throw(DomainError(
            display_details,
            "Unexpected output from xrandr when trying to determine rotation of real screen"
        ))
    end
end


### Android View

disable_autorotation!(::AndroidView) = run(`$ADB shell settings put system accelerometer_rotation 0`)
rotation(::AndroidView) = (Normal(), Right(), Inverted(), Left())[1+parse(Int, readchomp(`$ADB shell settings get system user_rotation`))]
rotate!(::AndroidView, ::Normal) = run(`$ADB shell settings put system user_rotation 0`)
rotate!(::AndroidView, ::Right) = run(`$ADB shell settings put system user_rotation 1`)
rotate!(::AndroidView, ::Inverted) = run(`$ADB shell settings put system user_rotation 2`)
rotate!(::AndroidView, ::Left) = run(`$ADB shell settings put system user_rotation 3`)


### AndroidWindow

# orientatation known for sure for AndroidWindow, but rotation is not
# so we overload orientation directly
function orientation(::AndroidWindow)
    window_details = split.(readlines(`wmctrl -l -G`), r" +"; limit=8)
    titles = last.(window_details)

    emu_ind = findfirst(contains(EMULATOR), titles)
    emu_width = parse(Int, window_details[emu_ind][5])
    emu_height =  parse(Int, window_details[emu_ind][6])
    return emu_width > emu_height ? Landscape() : Portrait()
end

# We don't have easy way to extract the current rotation of AndroidWindow from 
_current_android_window_rotation = Normal()
function rotation(w::AndroidWindow)
    # check it is compatible with the orientation
    #@assert orientation(w) == orientation(w, _current_android_window_rotation)
    return _current_android_window_rotation
end

send_to_emulator(keyseq) = run(`xdotool search  --desktop 0 --name "$EMULATOR"  windowactivate key $keyseq`)

function rotate!(w::AndroidWindow, t::Turn)
    _exectute_rotate!(w, t)
    global _current_android_window_rotation = rotate(_current_android_window_rotation, t)
end
_exectute_rotate!(::AndroidWindow, ::Clockwise) =  send_to_emulator(`ctrl+Right`)
_exectute_rotate!(::AndroidWindow, ::CounterClockwise) = send_to_emulator(`ctrl+Left`)
_exectute_rotate!(w::AndroidWindow, ::Flip) = send_to_emulator(`ctrl+Left ctrl+Left`)
_exectute_rotate!(::AndroidWindow, ::NoTurn) = nothing

rotate!(w::AndroidWindow, r::Rotation) = rotate!(w, needed_turn(rotation(w), r))

### Emulator: combining all the rotational controls

scale_up() = send_to_emulator(`ctrl+Up`)
scale_up_full() = send_to_emulator(`ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up`)

function _rotate!(::Emulator, wt, vt)
    disable_autorotation!(AndroidView())
    @sync begin
        @async rotate!(AndroidView(), vt)
        @async rotate!(AndroidWindow(), wt)
        @async scale_up_full()
    end
    return nothing
end

rotate!(e::Emulator, ::Portrait) = _rotate!(e, Normal(), Normal())
rotate!(e::Emulator, ::Landscape) = _rotate!(e, Left(), Right())

reorientate!() = rotate!(Emulator(), orientation(RealScreen()))

### Guessing Android Window Rotation
# This is partially based on the behavour of reorientate() 
guess_window_rotation() = @show guess_window_rotation(orientation(AndroidWindow()))
guess_window_rotation(::Portrait) = Normal()
guess_window_rotation(::Landscape) = Left()

function set_window_rotation_to_best_guess!()
    global _current_android_window_rotation = guess_window_rotation()
end
###########################

function is_running()
    titles = last.(split.(readlines(`wmctrl -l`), " "; limit=5))
    return any(contains(EMULATOR), titles)
end

# Sometimes will get errors if was trying to act while screen is black because it is mid-rotate.
is_ok_error(::Any) = false
is_ok_error(::ProcessFailedException) = true
is_ok_error(err::CompositeException) = all(is_ok_error, err)
is_ok_error(err::TaskFailedException) = is_ok_error(err.task.result)
function look_after_orientation!()
    while(true)
        try
            is_running() || return  # leave function once program closed
            reorientate!()
        catch err
            is_ok_error(err) || rethrow()
        end
        sleep(0.5)
    end
end


function ensure_started()
    is_running() && return
    # delete any lock files -- if it isn't running they should be there
    rm.(filter(endswith(".lock"), readdir(AVD_DIR; join=true)))
    @info "starting new emulator"
    run(`$(homedir())/Android/Sdk/emulator/emulator @oxphone`; wait=false)
    sleep(1.5)
    is_running() || error("could not start emulator")
end

function main()
    ensure_started()
    retry(set_window_rotation_to_best_guess!)()
    look_after_orientation!()
end

main()
