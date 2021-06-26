#! /usr/local/bin/julia-1.7
const EMULATOR = "Android Emulator"
const AVD_DIR = expanduser("~/.android/avd/oxphone.avd/")
const ADB = expanduser("~/Android/Sdk/platform-tools/adb")

struct NonfatalException <: Exception
    msg::String
end

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

function screen_size(::RealScreen)
    display_details = readlines(`xrandr -q`)[2]
    m = match(r"(\d+)x(\d+)\+0\+0", display_details)
    return parse.(Int, m.captures)
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
function orientation(w::AndroidWindow)
    width, height = screen_size(w)
    return width > height ? Landscape() : Portrait()
end

function screen_size(::AndroidWindow)
    window_details = split.(readlines(`wmctrl -l -G`), r" +"; limit=8)
    titles = last.(window_details)

    ind = findfirst(contains(EMULATOR), titles)
    width = parse(Int, window_details[ind][5])
    height =  parse(Int, window_details[ind][6])
    return width, height
end

function rotation(w::AndroidWindow)
    sys_details = readchomp(`$ADB shell dumpsys window displays`)
    m = match(r"mPredictedRotation=(\d)", sys_details)
    m isa Nothing && throw(NonfatalException("couldn't determine AndroidWindow rotation"))
    rot_id = parse(Int, m[1])
    return (Normal(), Left(), Inverted(), Right())[rot_id + 1]
end

send_to_emulator(keyseq) = run(`xdotool search  --desktop 0 --name "$EMULATOR"  windowactivate key --delay=40 $keyseq`)

function rotate!(w::AndroidWindow, t::Turn)
    _exectute_rotate!(w, t)
end
_exectute_rotate!(::AndroidWindow, ::Clockwise) =  send_to_emulator(`ctrl+Right`)
_exectute_rotate!(::AndroidWindow, ::CounterClockwise) = send_to_emulator(`ctrl+Left`)
_exectute_rotate!(w::AndroidWindow, ::Flip) = send_to_emulator(`ctrl+Left ctrl+Left`)
_exectute_rotate!(::AndroidWindow, ::NoTurn) = nothing

rotate!(w::AndroidWindow, r::Rotation) = rotate!(w, needed_turn(rotation(w), r))

### Emulator: combining all the rotational controls

scale_up() = send_to_emulator(`ctrl+Up`)
function scale_up_full()
    if 200 < minimum(screen_size(RealScreen()) .- screen_size(AndroidWindow()))
        # While sending keystokes is a more graceful transition, it can't get to the full size
        #send_to_emulator(`ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up ctrl+Up`)
        run(`wmctrl -r "$EMULATOR" -e 0,6,0,100000,100000`)
    end
end

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

###########################

function is_running()
    titles = last.(split.(readlines(`wmctrl -l`), " "; limit=5))
    return any(contains(EMULATOR), titles)
end

# Sometimes will get errors if was trying to act while screen is black because it is mid-rotate.
is_ok_error(::Any) = false
is_ok_error(::ProcessFailedException) = true
is_ok_error(::NonfatalException) = true
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
    look_after_orientation!()
end

main()
