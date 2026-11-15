% P2M4 Matlab
% D.Chmura
% 11/2/26  (cave sea theme + auto-reconnect added 11/14/26)
% Vibration Level Detection
% Listens for data from the pico and converts it to the current game state
% and changes that based on pico inputs.
% If the Pico crashes or gets unplugged, this keeps running and reconnects
% on its own as soon as the Pico comes back.

clear; clc; close all;

%% Settings
PICO_PORT = "";     % "" = auto pick the port, or pin it like "COM5"
BAUD = 9600;
IDLE_TIMEOUT = 10;  % seconds of no activity before going back to the start screen
NO_DATA_KICK = 3;   % seconds of silence before sending the Pico a soft reset
NO_DATA_DROP = 8;   % seconds of silence before closing the port and reconnecting

%% Cave sea color palette
C.abyss = [0.02 0.09 0.17];   % deep water background
C.card  = [0.05 0.19 0.30];   % slightly lighter panels
C.aqua  = [0.30 0.95 0.90];   % bioluminescent cyan
C.text  = [0.82 0.96 1.00];   % pale sea-foam text
C.glow  = [0.40 1.00 0.65];   % glowing green
C.coral = [1.00 0.42 0.45];   % coral red
C.gold  = [1.00 0.80 0.35];   % lantern gold

%% Build the interface
fig = uifigure("Name", "Olm Cavern - Vibration Detection", ...
    "Color", C.abyss, "Position", [100 100 900 620], ...
    "AutoResizeChildren", "off");

% Grid layout so everything stretches when the window is resized or fullscreen.
% Outer rows/columns are margins.
root = uigridlayout(fig, [10 5], ...
    "RowHeight", {12, 60, '1x', 32, 32, 32, 26, 46, 30, 10}, ...
    "ColumnWidth", {16, 32, '1x', '1.2x', 16}, ...
    "Padding", 0, "RowSpacing", 6, "ColumnSpacing", 12, ...
    "BackgroundColor", C.abyss);

titleLbl = uilabel(root, "Text", "OLM CAVERN  -  Vibration Detection", ...
    "FontSize", 28, "FontWeight", "bold", "FontColor", C.aqua);
titleLbl.Layout.Row = 2; titleLbl.Layout.Column = [2 4];

% Image drawn by me fr
im = uiimage(root, "ImageSource", "olm_image.png");
im.Layout.Row = 3; im.Layout.Column = [2 3];

% Gauge for displaying vibrations
g = uigauge(root, ...
    "BackgroundColor", C.card, "FontColor", C.text, ...
    "ScaleColors", [C.glow; C.gold; C.coral], ...
    "ScaleColorLimits", [0 60; 60 80; 80 100]);
g.Layout.Row = [3 6]; g.Layout.Column = 4;
g.Value = 0;

% Lamps for showing if a part is on each beam
startLamp = uilamp(root, "Color", C.glow);
startLamp.Layout.Row = 4; startLamp.Layout.Column = 2;
startLbl = uilabel(root, "Text", "Start Beam: clear", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
startLbl.Layout.Row = 4; startLbl.Layout.Column = 3;

endLamp = uilamp(root, "Color", C.glow);
endLamp.Layout.Row = 5; endLamp.Layout.Column = 2;
endLbl = uilabel(root, "Text", "End Beam: clear", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
endLbl.Layout.Row = 5; endLbl.Layout.Column = 3;

% Label for the start button
btnLbl = uilabel(root, "Text", "Start Button: not pressed", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
btnLbl.Layout.Row = 6; btnLbl.Layout.Column = [2 3];
btnPresses = 0;

% Two way slider for setting min and max for vibration detection
sldLbl = uilabel(root, "Text", "Adjust Accelerometer Sensitivity!", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.gold);
sldLbl.Layout.Row = 7; sldLbl.Layout.Column = [2 4];

sld = uislider(root, "range");
sld.Layout.Row = 8; sld.Layout.Column = [2 4];
sld.Step = 0.1;
sld.Limits = [0 10];
sld.Value = [1 7];
sld.FontColor = C.text;
sld.ValueChangedFcn = @(src, evt) disp(src.Value);

% Connection status + fullscreen button
statusLbl = uilabel(root, "Text", "Searching for Pico...", ...
    "FontSize", 14, "FontWeight", "bold", "FontColor", C.gold);
statusLbl.Layout.Row = 9; statusLbl.Layout.Column = [2 3];

fsBtn = uibutton(root, "Text", "Fullscreen (F11)", ...
    "FontWeight", "bold", "FontColor", C.abyss, "BackgroundColor", C.aqua);
fsBtn.Layout.Row = 9; fsBtn.Layout.Column = 4;
fsBtn.ButtonPushedFcn = @(~, ~) toggleFullscreen(fig, fsBtn);
fig.WindowKeyPressFcn = @(src, evt) onKey(src, evt, fsBtn);

% Start, win, and lose screens - each one covers the whole window
[startScreen, startTtl, startSub, startHint] = makeScreen(root, ...
    [0.02 0.16 0.24], "Start", C.aqua, ...
    "Press the start button to dive into the cavern", C);
[winScreen, winTtl, winSub, winHint] = makeScreen(root, ...
    [0.02 0.20 0.16], "Win", C.glow, ...
    "You made it through the cave without waking the olm up!", C);
[loseScreen, loseTtl, loseSub, loseHint] = makeScreen(root, ...
    [0.22 0.04 0.09], "Lose", C.coral, ...
    "Too much vibrations - the olm woke up...", C);
winScreen.Visible = "off";
loseScreen.Visible = "off";

% Disconnected screen - made last so it sits on top of everything
[connScreen, connTtl, connSub, connHint] = makeScreen(root, ...
    [0.07 0.06 0.20], "Pico lost", C.gold, ...
    "Plug in or restart the Pico - it will reconnect automatically", C);
connHint.Text = "Searching...";

% Scale the big text with the window size (so fullscreen looks right)
bigLbls = [startTtl winTtl loseTtl connTtl];
subLbls = [startSub winSub loseSub connSub startHint winHint loseHint connHint];
fig.SizeChangedFcn = @(src, ~) scaleFonts(src, bigLbls, subLbls, titleLbl);
scaleFonts(fig, bigLbls, subLbls, titleLbl);

%% Game state - "start", "playing", "win", or "lose"
gameState = "start";
startBeamOn = false;    % true when a part is on the start beam
lastActivity = tic;

% Vibration Level - ignore the warning, solely declaring the variable pulls
% up a physics demonstration
vibes = 0.0;
Brightness = 0.0;
history = zeros(1, 5);

% Vibration Threshold
vibrationThreshold = 1.0;
vibrationMax = 7.0;

%% Connection state
PicoObj = [];               % empty = not connected
picoPort = PICO_PORT;       % last port we connected on
pinned = PICO_PORT ~= "";   % only ever use the pinned port
lastData = tic;             % last time we heard anything from the Pico
lastRetry = tic;            % last connection attempt
lastPortCheck = tic;        % last time we checked the port still exists
kicked = false;             % already sent a soft reset for this silence
firstTry = true;

%% Main loop - runs until the window is closed
while isvalid(fig)

    % ---------- Not connected: keep trying, keep the UI alive ----------
    if isempty(PicoObj)
        if firstTry || toc(lastRetry) > 1
            firstTry = false;
            lastRetry = tic;
            [PicoObj, newPort] = connectPico(picoPort, pinned, BAUD);
            if ~isempty(PicoObj)
                picoPort = newPort;
                lastData = tic;
                lastPortCheck = tic;
                kicked = false;
                connScreen.Visible = "off";
                setStatus(statusLbl, "Pico connected on " + picoPort, C.glow);
                fprintf("Connected to Pico on %s\n", picoPort);
            else
                connScreen.Visible = "on";
                connHint.Text = "Searching... (" + string(datetime("now", "Format", "HH:mm:ss")) + ")";
                setStatus(statusLbl, "Searching for Pico...", C.gold);
            end
        end
        drawnow;
        pause(0.1);
        continue
    end

    % ---------- Connected ----------
    try
        % Get vibration values from slider component
        vibrationThreshold = sld.Value(1);   % left handle
        vibrationMax = sld.Value(2);         % right handle

        % Read every message waiting from the pico - no flush, or we would
        % throw away the button and beam messages that only get sent once
        while PicoObj.NumBytesAvailable > 0
            PicoMsg = readline(PicoObj);
            if isempty(PicoMsg)
                break   % timed out on a partial line, grab it next loop
            end
            PicoMsg = strtrim(PicoMsg);
            if PicoMsg == ""
                continue
            end
            lastData = tic;
            if kicked
                kicked = false;
                setStatus(statusLbl, "Pico connected on " + picoPort, C.glow);
            end

            % Check if we recognize the message
            if startsWith(PicoMsg, 'S1:')
                % Get gauge position from message
                vibes = sscanf(PicoMsg, 'S1:%f');
                if isempty(vibes)
                    continue
                end
                if vibes < vibrationThreshold
                    Brightness = 0;
                elseif vibes > vibrationMax
                    Brightness = int32(100.0);
                else
                    Brightness = int32(((vibes - vibrationThreshold) / (vibrationMax - vibrationThreshold)) * 100.0);
                end

                % Any vibration above the threshold counts as activity
                if Brightness > 0
                    lastActivity = tic;
                end

                % Set gauge
                history = [history(2:end) double(Brightness)];
                g.Value = mean(history);

                % Too much vibration while playing means you lose
                if gameState == "playing" && g.Value >= 100
                    gameState = "lose";
                    loseScreen.Visible = "on";
                end

            elseif startsWith(PicoMsg, 'B1:')
                % Start button was pressed
                btnPresses = btnPresses + 1;
                btnLbl.Text = sprintf("Start Button: pressed (%d)", btnPresses);
                lastActivity = tic;

                % Button starts the game from the start screen (only if a part
                % is on the start beam), and goes back to the start screen from
                % the win or lose screen
                if gameState == "start" && startBeamOn
                    gameState = "playing";
                    history = zeros(1, 5);
                    startScreen.Visible = "off";
                elseif gameState == "win" || gameState == "lose"
                    gameState = "start";
                    winScreen.Visible = "off";
                    loseScreen.Visible = "off";
                    startScreen.Visible = "on";
                end

            elseif startsWith(PicoMsg, 'B2:')
                % Start beam changed - 1 = part on the beam, 0 = clear
                beamVal = sscanf(PicoMsg, 'B2:%d');
                if ~isscalar(beamVal)
                    continue    % garbled message - keep the last known state
                end
                startBeamOn = beamVal == 1;
                lastActivity = tic;
                if startBeamOn
                    startLamp.Color = C.coral;
                    startLbl.Text = "Start Beam: part on";
                else
                    startLamp.Color = C.glow;
                    startLbl.Text = "Start Beam: clear";
                end

            elseif startsWith(PicoMsg, 'B3:')
                % End beam changed - 1 = part on the beam, 0 = clear
                beamVal = sscanf(PicoMsg, 'B3:%d');
                if ~isscalar(beamVal)
                    continue    % garbled message - keep the last known state
                end
                lastActivity = tic;
                if beamVal == 1
                    endLamp.Color = C.coral;
                    endLbl.Text = "End Beam: part on";

                    % Part made it to the end while playing means you win
                    if gameState == "playing"
                        gameState = "win";
                        winScreen.Visible = "on";
                    end
                else
                    endLamp.Color = C.glow;
                    endLbl.Text = "End Beam: clear";
                end

            elseif startsWith(PicoMsg, 'E1:')
                % Pico reported a sensor problem (but is still running)
                setStatus(statusLbl, "Pico: " + extractAfter(PicoMsg, 3), C.coral);

            else
                % Anything else (tracebacks, boot messages) goes to the
                % command window so you can see why the Pico crashed
                fprintf("[Pico] %s\n", PicoMsg);
            end
        end

        % ---------- Pico went quiet ----------
        % The Pico normally talks ~100 times a second, so silence means the
        % script crashed. Ctrl-C Ctrl-D soft reboots it, which re-runs main.py.
        if ~kicked && toc(lastData) > NO_DATA_KICK
            kicked = true;
            fprintf("Pico went quiet - sending soft reset\n");
            setStatus(statusLbl, "Pico went quiet - restarting it...", C.gold);
            write(PicoObj, uint8([3 3 4]), "uint8");
        end
        if toc(lastData) > NO_DATA_DROP
            error("Pico:silent", "No data from the Pico for %d seconds", NO_DATA_DROP);
        end

        % Port disappeared (unplugged / USB reset)
        if toc(lastPortCheck) > 1
            lastPortCheck = tic;
            if ~any(serialportlist("all") == picoPort)
                error("Pico:gone", "%s disappeared", picoPort);
            end
        end

        % Send the brightness back to the Pico (only while it is talking,
        % so we don't spam the REPL if the script has crashed)
        if toc(lastData) < 1
            writeline(PicoObj, sprintf('a%d', Brightness));
        end

    catch err
        % Lost the Pico - close the port and go back to searching
        if ~isvalid(fig)
            break
        end
        fprintf("Lost connection: %s\n", err.message);
        try
            delete(PicoObj);
        catch
        end
        PicoObj = [];
        lastRetry = tic;

        % Reset everything - the Pico re-sends its beam states when it boots
        Brightness = 0;
        history = zeros(1, 5);
        g.Value = 0;
        gameState = "start";
        winScreen.Visible = "off";
        loseScreen.Visible = "off";
        startScreen.Visible = "on";
        connScreen.Visible = "on";
        setStatus(statusLbl, "Pico lost - searching...", C.coral);
        continue
    end

    % Window was closed while we were reading - stop here
    if ~isvalid(fig)
        break
    end

    % No activity for IDLE_TIMEOUT seconds - go back to the start screen
    if gameState ~= "start" && toc(lastActivity) > IDLE_TIMEOUT
        gameState = "start";
        history = zeros(1, 5);
        winScreen.Visible = "off";
        loseScreen.Visible = "off";
        startScreen.Visible = "on";
    end

    % Only show "Move to start" if the part isn't on the start beam
    if startBeamOn
        hintVis = "off";
    else
        hintVis = "on";
    end
    startHint.Visible = hintVis;
    winHint.Visible = hintVis;
    loseHint.Visible = hintVis;

    drawnow;      % Update the interface
    pause(0.05);  % Slow down so we can read it (also keeps the Pico's buffer from flooding)
end

% Window closed - turn the LEDs off and hand the port back
if ~isempty(PicoObj)
    try
        writeline(PicoObj, "a0");
    catch
    end
    delete(PicoObj);
end
clear PicoObj;


%% ===================== Helper functions =====================

function [obj, port] = connectPico(preferred, pinned, baud)
% Try to open the Pico's serial port. Returns [] if it isn't there yet.
obj = [];
port = "";
ports = serialportlist("available");
if isempty(ports)
    return
end
if preferred ~= "" && any(ports == preferred)
    port = preferred;
elseif pinned
    return              % pinned port isn't back yet
else
    port = ports(end);
end
try
    obj = serialport(port, baud, "Timeout", 0.5);
    configureTerminator(obj, "LF");
    flush(obj);
catch
    obj = [];           % port exists but isn't ready yet (Pico still booting)
    port = "";
end
end

function setStatus(lbl, txt, col)
lbl.Text = txt;
lbl.FontColor = col;
end

function [pnl, ttl, sub, hint] = makeScreen(root, bgCol, titleTxt, titleCol, subTxt, C)
% Full-window overlay: solid colored background with big title text on top
pnl = uipanel(root, "BorderType", "none", "BackgroundColor", bgCol);
pnl.Layout.Row = [1 10];
pnl.Layout.Column = [1 5];
gl = uigridlayout(pnl, [5 1], "RowHeight", {'1x', '0.9x', '0.18x', '0.18x', '0.6x'}, ...
    "ColumnWidth", {'1x'}, "Padding", 0, "RowSpacing", 0, ...
    "BackgroundColor", bgCol);
ttl = uilabel(gl, "Text", titleTxt, "FontSize", 80, "FontWeight", "bold", ...
    "FontColor", titleCol, "HorizontalAlignment", "center", ...
    "VerticalAlignment", "bottom");
ttl.Layout.Row = 2;
sub = uilabel(gl, "Text", subTxt, "FontSize", 22, "FontColor", C.text, ...
    "HorizontalAlignment", "center");
sub.Layout.Row = 3;
hint = uilabel(gl, "Text", "Move to start", "FontSize", 24, ...
    "FontWeight", "bold", "FontColor", C.gold, "HorizontalAlignment", "center");
hint.Layout.Row = 4;
end

function scaleFonts(fig, bigLbls, subLbls, titleLbl)
% Grow/shrink text with the window height
h = fig.Position(4);
for k = 1:numel(bigLbls)
    bigLbls(k).FontSize = max(48, round(h * 0.15));
end
for k = 1:numel(subLbls)
    subLbls(k).FontSize = max(18, round(h * 0.035));
end
titleLbl.FontSize = max(24, round(h * 0.045));
end

function toggleFullscreen(fig, btn)
if fig.WindowState == "fullscreen"
    fig.WindowState = "normal";
    btn.Text = "Fullscreen (F11)";
else
    fig.WindowState = "fullscreen";
    btn.Text = "Exit fullscreen (Esc)";
end
end

function onKey(fig, evt, btn)
switch evt.Key
    case 'f11'
        toggleFullscreen(fig, btn);
    case 'escape'
        if fig.WindowState == "fullscreen"
            toggleFullscreen(fig, btn);
        end
end
end
