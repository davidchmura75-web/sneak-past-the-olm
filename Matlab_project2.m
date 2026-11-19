% P2M4 Matlab
% D.Chmura
% 11/2/26
% Vibration Level Detection

function Matlab_project2

clc; close all;

% Stop a game left running from an earlier run
oldTimers = timerfindall("Tag", "OlmCavernLoop");
if ~isempty(oldTimers)
    stop(oldTimers);
    delete(oldTimers(isvalid(oldTimers)));
end

%% Settings
PICO_PORT = "";
BAUD = 9600;
IDLE_TIMEOUT = 20;  % seconds until reset
NO_DATA_KICK = 3;   % seconds until soft reset
NO_DATA_DROP = 8;   % seconds until reconnect
ROUND_LOG = fullfile(fileparts(mfilename("fullpath")), "round_data.txt");  % one line per round
LEADERBOARD = fullfile(fileparts(mfilename("fullpath")), "leaderboard.txt"); % every win, fastest first
LB_SHOW = 5;        % how many places to show on the win screen

%% Colors
C.abyss = [0.02 0.09 0.17];
C.card  = [0.05 0.19 0.30];
C.aqua  = [0.30 0.95 0.90];
C.text  = [0.82 0.96 1.00];
C.glow  = [0.40 1.00 0.65];
C.coral = [1.00 0.42 0.45];
C.gold  = [1.00 0.80 0.35];

%% Font
% Oh Whale (fonts/OhWhale-oYZq.ttf)
FONT = "Oh Whale";
if ~any(strcmp(listfonts, FONT))
    fontSrc = fullfile(fileparts(mfilename("fullpath")), "fonts", "OhWhale-oYZq.ttf");
    fontDir = fullfile(getenv("LOCALAPPDATA"), "Microsoft", "Windows", "Fonts");
    if ~isfolder(fontDir), mkdir(fontDir); end
    fontDst = fullfile(fontDir, "OhWhale-oYZq.ttf");
    copyfile(fontSrc, fontDst);
    system("reg add ""HKCU\Software\Microsoft\Windows NT\CurrentVersion\Fonts"" " + ...
        "/v ""Oh Whale (TrueType)"" /t REG_SZ /d """ + fontDst + """ /f");
    warning("Installed the Oh Whale font - restart MATLAB if it doesn't show up.");
end

%% Main page window
% Use second monitor
mons = get(groot, "MonitorPositions");
if size(mons, 1) > 1
    mainPos = [mons(2,1)+60 mons(2,2)+60 900 620];
else
    mainPos = [520 120 900 620];
end

fig = uifigure("Name", "Olm Cavern", ...
    "Color", C.abyss, "Position", mainPos, ...
    "AutoResizeChildren", "off");

%% Admin page window
adminFig = uifigure("Name", "Olm Cavern - Admin", ...
    "Color", C.abyss, "Position", [40 60 1100 680], ...
    "AutoResizeChildren", "off");

aRoot = uigridlayout(adminFig, [6 2], ...
    "RowHeight", {40, '1x', 26, 46, 30, 4}, ...
    "ColumnWidth", {'1.7x', '1x'}, ...
    "Padding", [16 10 16 10], "RowSpacing", 6, "ColumnSpacing", 14, ...
    "BackgroundColor", C.abyss);

adminTtl = uilabel(aRoot, "Text", "ADMIN  -  Olm Cavern", ...
    "FontName", FONT, "FontSize", 24,"FontWeight", "bold", "FontColor", C.aqua);
adminTtl.Layout.Row = 1; adminTtl.Layout.Column = [1 2];

% Main page preview
previewPnl = uipanel(aRoot, "Title", "Main page preview", ...
    "BackgroundColor", C.abyss, "ForegroundColor", C.text, ...
    "FontWeight", "bold", "AutoResizeChildren", "off");
previewPnl.Layout.Row = 2; previewPnl.Layout.Column = 1;

% Sensor panel
sensPnl = uipanel(aRoot, "Title", "Sensors", ...
    "BackgroundColor", C.card, "ForegroundColor", C.text, "FontWeight", "bold");
sensPnl.Layout.Row = 2; sensPnl.Layout.Column = 2;
sg = uigridlayout(sensPnl, [9 2], ...
    "RowHeight", {32, 32, 32, 32, 32, 32, 32, 32, '1x'}, ...
    "ColumnWidth", {28, '1x'}, "Padding", 12, "RowSpacing", 8, ...
    "BackgroundColor", C.card);

% Beam lamps
startLamp = uilamp(sg, "Color", C.glow);
startLamp.Layout.Row = 1; startLamp.Layout.Column = 1;
startLbl = uilabel(sg, "Text", "Start Beam: clear", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
startLbl.Layout.Row = 1; startLbl.Layout.Column = 2;

endLamp = uilamp(sg, "Color", C.glow);
endLamp.Layout.Row = 2; endLamp.Layout.Column = 1;
endLbl = uilabel(sg, "Text", "End Beam: clear", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
endLbl.Layout.Row = 2; endLbl.Layout.Column = 2;

% Start button
btnLbl = uilabel(sg, "Text", "Start Button: not pressed", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
btnLbl.Layout.Row = 3; btnLbl.Layout.Column = [1 2];
btnPresses = 0;

% Readouts
vibLbl = uilabel(sg, "Text", "Accelerometer: --", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
vibLbl.Layout.Row = 4; vibLbl.Layout.Column = [1 2];
brtLbl = uilabel(sg, "Text", "LED Brightness: 0", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
brtLbl.Layout.Row = 5; brtLbl.Layout.Column = [1 2];
stateLbl = uilabel(sg, "Text", "Game State: start", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.gold);
stateLbl.Layout.Row = 6; stateLbl.Layout.Column = [1 2];
idleLbl = uilabel(sg, "Text", "Idle: 0 s", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
idleLbl.Layout.Row = 7; idleLbl.Layout.Column = [1 2];
servoLbl = uilabel(sg, "Text", "Servo: --", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
servoLbl.Layout.Row = 8; servoLbl.Layout.Column = [1 2];

% Sensitivity slider
sldLbl = uilabel(aRoot, "Text", "Adjust Accelerometer Sensitivity!", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.gold);
sldLbl.Layout.Row = 3; sldLbl.Layout.Column = [1 2];

sld = uislider(aRoot, "range");
sld.Layout.Row = 4; sld.Layout.Column = [1 2];
sld.Step = 0.1;
sld.Limits = [0 10];
sld.Value = [1 7];
sld.FontColor = C.text;

% Status and fullscreen
statusLbl = uilabel(aRoot, "Text", "Searching for Pico...", ...
    "FontSize", 14, "FontWeight", "bold", "FontColor", C.gold);
statusLbl.Layout.Row = 5; statusLbl.Layout.Column = 1;

fsBtn = uibutton(aRoot, "Text", "Main page fullscreen (F11)", ...
    "FontWeight", "bold", "FontColor", C.abyss, "BackgroundColor", C.aqua);
fsBtn.Layout.Row = 5; fsBtn.Layout.Column = 2;

% Button/keys leave a request
fsBtn.ButtonPushedFcn = @(~, ~) set(fsBtn, "UserData", "f11");
fig.WindowKeyPressFcn = @(~, evt) set(fsBtn, "UserData", evt.Key);
adminFig.WindowKeyPressFcn = @(~, evt) set(fsBtn, "UserData", evt.Key);

%% Game page (built twice)
% 1 = main page, 2 = admin preview
parents = {fig, previewPnl};

% Overlay screens: start, win, lose, Pico lost
scrBg    = [0.02 0.16 0.24; 0.02 0.20 0.16; 0.22 0.04 0.09; 0.07 0.06 0.20];
scrTitle = ["Start", "Win", "Lose", "Pico lost"];
scrColor = [C.aqua; C.glow; C.coral; C.gold];
scrImg   = ["olm_start.png", "confused_olm.png", "alert_olm.png", "confused_olm.png"];
scrSub   = ["Press the start button to dive into the cavern", ...
            "You made it through the cave without waking the olm up!", ...
            "Too much vibrations - the olm woke up...", ...
            "Plug in or restart the Pico - it will reconnect automatically"];

gauges  = gobjects(2, 1);
titles  = gobjects(2, 1);
screens = gobjects(2, 4);
bigLbls = gobjects(2, 4);
subLbls = gobjects(2, 4);
hints   = gobjects(2, 4);
lbLbls  = gobjects(2, 1);   % leaderboard on the win screen

for k = 1:2
    grid = uigridlayout(parents{k}, [4 4], ...
        "RowHeight", {'0.03x', '0.12x', '1x', '0.04x'}, ...
        "ColumnWidth", {'0.02x', '1.3x', '1x', '0.02x'}, ...
        "Padding", 0, "RowSpacing", 6, "ColumnSpacing", 12, ...
        "BackgroundColor", C.abyss);

    titles(k) = uilabel(grid, "Text", "OLM CAVERN  -  Vibration Detection", ...
        "FontName", FONT, "FontSize", 28, "FontWeight", "bold", "FontColor", C.aqua);
    titles(k).Layout.Row = 2; titles(k).Layout.Column = [2 3];

    % Drawn by me fr
    img = uiimage(grid, "ImageSource", "olm_image.png");
    img.Layout.Row = 3; img.Layout.Column = 2;

    % Vibration gauge
    gauges(k) = uigauge(grid, ...
        "BackgroundColor", C.card, "FontColor", C.text, ...
        "ScaleColors", [C.glow; C.gold; C.coral], ...
        "ScaleColorLimits", [0 60; 60 80; 80 100]);
    gauges(k).Layout.Row = 3; gauges(k).Layout.Column = 3;

    % Full-page overlays
    for s = 1:4
        pnl = uipanel(grid, "BorderType", "none", "BackgroundColor", scrBg(s,:));
        pnl.Layout.Row = [1 4]; pnl.Layout.Column = [1 4];

        % Every page has an olm above the title
        rows = {'0.35x', '1.2x', '0.55x', '0.15x', '0.15x', '0.1x'};
        ttlRow = 3;
        gl = uigridlayout(pnl, [numel(rows) 1], "RowHeight", rows, ...
            "ColumnWidth", {'1x'}, "Padding", 0, "RowSpacing", 0, ...
            "BackgroundColor", scrBg(s,:));
        if s == 2
            % Win page: olm on the left, leaderboard on the right
            winRow = uigridlayout(gl, [1 2], "ColumnWidth", {'1x', '1x'}, ...
                "Padding", 0, "ColumnSpacing", 20, "BackgroundColor", scrBg(s,:));
            winRow.Layout.Row = 2;
            olm = uiimage(winRow, "ImageSource", scrImg(s), "ScaleMethod", "fit");
            olm.Layout.Column = 1;
            lbLbls(k) = uilabel(winRow, "Text", "", "Interpreter", "html", ...
                "FontName", FONT, "FontSize", 22, "FontColor", C.text, ...
                "HorizontalAlignment", "left", "VerticalAlignment", "center");
            lbLbls(k).Layout.Column = 2;
        else
            olm = uiimage(gl, "ImageSource", scrImg(s), "ScaleMethod", "fit");
            olm.Layout.Row = 2;
        end

        bigLbls(k,s) = uilabel(gl, "Text", scrTitle(s), "FontName", FONT, "FontSize", 80, ...
            "FontWeight", "bold", "FontColor", scrColor(s,:), ...
            "HorizontalAlignment", "center", "VerticalAlignment", "bottom");
        bigLbls(k,s).Layout.Row = ttlRow;
        subLbls(k,s) = uilabel(gl, "Text", scrSub(s), "FontName", FONT, "FontSize", 22, ...
            "FontColor", C.text, "HorizontalAlignment", "center");
        subLbls(k,s).Layout.Row = ttlRow + 1;
        hints(k,s) = uilabel(gl, "Text", "Move to start", "FontName", FONT, "FontSize", 24, ...
            "FontWeight", "bold", "FontColor", C.gold, "HorizontalAlignment", "center");
        hints(k,s).Layout.Row = ttlRow + 2;

        screens(k,s) = pnl;
    end
    hints(k,4).Text = "Searching...";
end

lastHeights = [0 0];

%% Game state
gameState = "start";    % start/playing/win/lose
startBeamOn = false;
lastActivity = tic;
servoSent = -1;         % last servo angle sent to the Pico (-1 = not sent yet)
servoConfirmed = -1;    % last servo angle the Pico reported back (-1 = unknown)
lastServoSend = tic;

vibes = 0.0;
Brightness = 0.0;
history = zeros(1, 5);

vibrationThreshold = 1.0;
vibrationMax = 7.0;

% Current round stats (reset when a round starts)
roundTimer = tic;
roundSum = 0;       % sum of accelerometer readings this round
roundCount = 0;     % number of readings this round
roundPeak = 0;      % highest accelerometer reading this round

% Leaderboard (name, time, date) - loaded from leaderboard.txt
board = loadBoard();

%% Connection state
PicoObj = [];
picoPort = PICO_PORT;
pinned = PICO_PORT ~= "";
lastData = tic;
lastRetry = tic;
lastPortCheck = tic;
kicked = false;
firstTry = true;

%% Game loop
% Runs on a timer so MATLAB stays free between ticks
% (a while loop keeps MATLAB busy and VS Code shuts it down)
gameTimer = timer("Tag", "OlmCavernLoop", ...
    "ExecutionMode", "fixedSpacing", "Period", 0.05, ...
    "BusyMode", "drop", ...
    "TimerFcn", @(~, ~) safeTick(), ...
    "StopFcn", @(~, ~) shutdown());

% Closing either window stops the game
fig.CloseRequestFcn = @(~, ~) stopGame();
adminFig.CloseRequestFcn = @(~, ~) stopGame();

start(gameTimer);
    %% One tick of the game
    function safeTick()
        try
            gameTick();
        catch tickErr
            % Keep the game running if something unexpected goes wrong
            fprintf("Game tick error: %s\n", tickErr.message);
        end
    end

    function gameTick()
        if ~isvalid(fig) || ~isvalid(adminFig)
            stopGame();
            return
        end

        % Fullscreen request
        key = "";
        if ~isempty(fsBtn.UserData)
            key = string(fsBtn.UserData);
            fsBtn.UserData = [];
        end
        if key == "f11" || (key == "escape" && fig.WindowState == "fullscreen")
            if fig.WindowState == "fullscreen"
                fig.WindowState = "normal";
                fsBtn.Text = "Main page fullscreen (F11)";
            else
                fig.WindowState = "fullscreen";
                fsBtn.Text = "Exit main fullscreen (Esc)";
            end
        end

        % Text scales with size
        heights = [fig.Position(4) previewPnl.Position(4)];
        for n = 1:2
            if heights(n) ~= lastHeights(n)
                h = heights(n);
                set(bigLbls(n,:), "FontSize", max(16, round(h * 0.15)));
                set([subLbls(n,:) hints(n,:)], "FontSize", max(8, round(h * 0.035)));
                lbLbls(n).FontSize = max(8, round(h * 0.03));
                titles(n).FontSize = max(10, round(h * 0.045));
            end
        end
        lastHeights = heights;

        % Show screen for state
        set(screens(:,1), "Visible", gameState == "start");
        set(screens(:,2), "Visible", gameState == "win");
        set(screens(:,3), "Visible", gameState == "lose");
        set(screens(:,4), "Visible", isempty(PicoObj));
        set(hints(:,1:3), "Visible", ~startBeamOn);

        % Admin readouts
        stateLbl.Text = "Game State: " + gameState;
        if gameState == "win" || gameState == "lose"
            idleLbl.Text = sprintf("Idle: %.0f s (resets at %d s)", toc(lastActivity), IDLE_TIMEOUT);
        else
            idleLbl.Text = "Idle: -- (only on win/lose)";
        end

        % Not connected
        if isempty(PicoObj)
            if firstTry || toc(lastRetry) > 1
                firstTry = false;
                lastRetry = tic;

                % Pick a port
                ports = serialportlist("available");
                tryPort = "";
                if any(ports == picoPort)
                    tryPort = picoPort;
                elseif ~pinned && ~isempty(ports)
                    tryPort = ports(end);
                end

                % Try opening it
                if tryPort ~= ""
                    try
                        PicoObj = serialport(tryPort, BAUD, "Timeout", 0.5);
                        configureTerminator(PicoObj, "LF");
                        flush(PicoObj);
                    catch
                        PicoObj = [];   % still booting
                    end
                end

                if ~isempty(PicoObj)
                    picoPort = tryPort;
                    lastData = tic;
                    lastPortCheck = tic;
                    kicked = false;
                    servoSent = -1;     % resend servo position to the new connection
                    servoConfirmed = -1;
                    set(screens(:,4), "Visible", "off");
                    set(statusLbl, "Text", "Pico connected on " + picoPort, "FontColor", C.glow);
                    fprintf("Connected to Pico on %s\n", picoPort);
                else
                    set(hints(:,4), "Text", "Searching... (" + ...
                        string(datetime("now", "Format", "HH:mm:ss")) + ")");
                    set(statusLbl, "Text", "Searching for Pico...", "FontColor", C.gold);
                end
            end
            drawnow;
            return
        end

        % Connected
        try
            vibrationThreshold = sld.Value(1);
            vibrationMax = sld.Value(2);

            % Read all messages
            while PicoObj.NumBytesAvailable > 0
                PicoMsg = readline(PicoObj);
                if isempty(PicoMsg)
                    break   % partial line
                end
                PicoMsg = strtrim(PicoMsg);
                if PicoMsg == ""
                    continue
                end
                lastData = tic;
                if kicked
                    kicked = false;
                    set(statusLbl, "Text", "Pico connected on " + picoPort, "FontColor", C.glow);
                end

                if startsWith(PicoMsg, 'S1:')
                    % Accelerometer
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


                    history = [history(2:end) double(Brightness)];
                    gaugeVal = mean(history);
                    set(gauges, "Value", gaugeVal);
                    vibLbl.Text = sprintf("Accelerometer: %.2f", vibes);

                    % Round stats
                    if gameState == "playing"
                        roundSum = roundSum + vibes;
                        roundCount = roundCount + 1;
                        roundPeak = max(roundPeak, vibes);
                    end

                    % Too much vibration
                    if gameState == "playing" && gaugeVal >= 100
                        gameState = "lose";
                        lastActivity = tic;   % start idle countdown on lose screen
                        logRound("lose");
                    end

                elseif startsWith(PicoMsg, 'B1:')
                    % Start button
                    btnPresses = btnPresses + 1;
                    btnLbl.Text = sprintf("Start Button: pressed (%d)", btnPresses);
                    lastActivity = tic;

                    if gameState == "start" && startBeamOn
                        gameState = "playing";
                        history = zeros(1, 5);
                        roundTimer = tic;
                        roundSum = 0;
                        roundCount = 0;
                        roundPeak = 0;
                    elseif gameState == "win" || gameState == "lose"
                        gameState = "start";
                    end

                elseif startsWith(PicoMsg, 'B2:')
                    % Start beam
                    beamVal = sscanf(PicoMsg, 'B2:%d');
                    if ~isscalar(beamVal)
                        continue    % garbled message
                    end
                    startBeamOn = beamVal == 1;
                    if startBeamOn
                        startLamp.Color = C.coral;
                        startLbl.Text = "Start Beam: part on";
                    else
                        startLamp.Color = C.glow;
                        startLbl.Text = "Start Beam: clear";
                    end

                elseif startsWith(PicoMsg, 'B3:')
                    % End beam
                    beamVal = sscanf(PicoMsg, 'B3:%d');
                    if ~isscalar(beamVal)
                        continue    % garbled message
                    end
                    if beamVal == 1
                        endLamp.Color = C.coral;
                        endLbl.Text = "End Beam: part on";
                        if gameState == "playing"
                            gameState = "win";
                            lastActivity = tic;   % start idle countdown on win screen
                            logRound("win");
                            addWinner(toc(roundTimer));
                        end
                    else
                        endLamp.Color = C.glow;
                        endLbl.Text = "End Beam: clear";
                    end

                elseif startsWith(PicoMsg, 'V1:')
                    % Servo moved (Pico confirms the angle it set)
                    angleVal = sscanf(PicoMsg, 'V1:%d');
                    if isscalar(angleVal)
                        servoConfirmed = angleVal;
                        servoLbl.Text = sprintf("Servo: %d%s  (Pico confirmed %s)", angleVal, char(176), ...
                            string(datetime("now", "Format", "HH:mm:ss")));
                        fprintf("Servo confirmed at %d deg\n", angleVal);
                    end

                elseif startsWith(PicoMsg, 'E1:')
                    % Sensor error
                    set(statusLbl, "Text", "Pico: " + extractAfter(PicoMsg, 3), "FontColor", C.coral);

                else
                    fprintf("[Pico] %s\n", PicoMsg);
                end
            end

            % Pico went quiet
            if ~kicked && toc(lastData) > NO_DATA_KICK
                kicked = true;
                fprintf("Pico went quiet - sending soft reset\n");
                set(statusLbl, "Text", "Pico went quiet - restarting it...", "FontColor", C.gold);
                write(PicoObj, uint8([3 3 4]), "uint8");
            end
            if toc(lastData) > NO_DATA_DROP
                error("Pico:silent", "No data from the Pico for %d seconds", NO_DATA_DROP);
            end

            % Port unplugged
            if toc(lastPortCheck) > 1
                lastPortCheck = tic;
                if ~any(serialportlist("all") == picoPort)
                    error("Pico:gone", "%s disappeared", picoPort);
                end
            end

            % LEDs only while playing
            if gameState == "playing"
                ledVal = Brightness;
            else
                ledVal = 0;
            end
            brtLbl.Text = sprintf("LED Brightness: %d", ledVal);
            if toc(lastData) < 1
                writeline(PicoObj, sprintf('a%d', ledVal));
            end

            % Servo: 180 on the lose screen, back to 0 on the home screen
            if gameState == "lose"
                servoAngle = 180;
            elseif gameState == "start"
                servoAngle = 0;
            else
                servoAngle = servoSent;     % keep where it is
            end
            % Send on change, and keep resending once a second until the Pico confirms
            % (covers commands lost while the Pico was booting or after a soft reset)
            if servoAngle >= 0 && (servoAngle ~= servoSent || ...
                    (servoConfirmed ~= servoAngle && toc(lastServoSend) > 1))
                writeline(PicoObj, sprintf('s%d', servoAngle));
                lastServoSend = tic;
                if servoAngle ~= servoSent
                    fprintf("Servo -> %d deg\n", servoAngle);
                end
                servoSent = servoAngle;
                if servoConfirmed ~= servoAngle
                    servoLbl.Text = sprintf("Servo: sent %d%s, waiting for Pico...", servoAngle, char(176));
                end
            end

        catch err
            % Lost the Pico
            if ~isvalid(fig) || ~isvalid(adminFig)
                stopGame();
                return
            end
            fprintf("Lost connection: %s\n", err.message);
            try
                delete(PicoObj);
            catch
            end
            PicoObj = [];
            lastRetry = tic;

            % Reset everything
            Brightness = 0;
            history = zeros(1, 5);
            set(gauges, "Value", 0);
            brtLbl.Text = "LED Brightness: 0";
            vibLbl.Text = "Accelerometer: --";
            servoLbl.Text = "Servo: --";
            if gameState == "playing"
                logRound("disconnected");
            end
            gameState = "start";
            set(hints(:,4), "Text", "Searching...");
            set(statusLbl, "Text", "Pico lost - searching...", "FontColor", C.coral);
            return
        end

        % Idle reset
        if (gameState == "win" || gameState == "lose") && toc(lastActivity) > IDLE_TIMEOUT
            gameState = "start";
            history = zeros(1, 5);
        end

        drawnow;
    end

    %% Stop the timer (its StopFcn does the cleanup)
    function stopGame()
        if isvalid(gameTimer) && gameTimer.Running == "on"
            stop(gameTimer);
        else
            shutdown();
        end
    end

    %% Leaderboard: read leaderboard.txt (name,time_s,date_time)
    function b = loadBoard()
        b = struct("name", {}, "time", {}, "date", {});
        if ~isfile(LEADERBOARD)
            return
        end
        try
            lines = readlines(LEADERBOARD);
            for i = 1:numel(lines)
                parts = split(strtrim(lines(i)), ",");
                t = str2double(parts(min(2, end)));
                if numel(parts) < 3 || isnan(t)
                    continue    % header, blank or broken line
                end
                b(end+1) = struct("name", parts(1), "time", t, "date", parts(3)); %#ok<AGROW>
            end
            [~, order] = sort([b.time]);
            b = b(order);
        catch lbErr
            fprintf("Could not read leaderboard: %s\n", lbErr.message);
        end
    end

    %% Leaderboard: random unused name like "Sneaky Gecko 42"
    function name = makeName()
        adjs  = ["Sneaky", "Silent", "Quiet", "Tiptoe", "Shadow", "Stealthy", "Gentle", ...
                 "Hushed", "Misty", "Velvet", "Sleepy", "Soft-Step", "Careful", "Ghostly"];
        nouns = ["Olm", "Gecko", "Newt", "Bat", "Shrimp", "Crayfish", "Salamander", ...
                 "Glowworm", "Cavefish", "Spelunker", "Pebble", "Axolotl", "Beetle", "Mole"];
        taken = string({board.name});
        for tries = 1:200
            name = adjs(randi(numel(adjs))) + " " + nouns(randi(numel(nouns))) + " " + randi(99);
            if ~any(taken == name)
                return
            end
        end
        name = name + " " + string(numel(board) + 1);   % very unlikely fallback
    end

    %% Leaderboard: add a winner, save, and show it on the win screen
    function addWinner(t)
        name = makeName();
        board(end+1) = struct("name", name, "time", t, ...
            "date", string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")));
        [~, order] = sort([board.time]);
        board = board(order);
        pos = find(string({board.name}) == name, 1);

        % Save the whole board, fastest first
        try
            fid = fopen(LEADERBOARD, "w");
            if fid < 0
                error("could not open %s", LEADERBOARD);
            end
            closeFid = onCleanup(@() fclose(fid));
            fprintf(fid, "name,time_s,date_time\n");
            for i = 1:numel(board)
                fprintf(fid, "%s,%.2f,%s\n", board(i).name, board(i).time, board(i).date);
            end
            clear closeFid
        catch lbErr
            fprintf("Could not save leaderboard: %s\n", lbErr.message);
        end

        % Win screen text
        set(subLbls(:,2), "Text", sprintf("You are %s  -  #%d of %d  (%.1f s)", ...
            name, pos, numel(board), t));
        set(lbLbls, "Text", boardHtml(pos));
        fprintf("Leaderboard: %s placed #%d of %d with %.2f s\n", name, pos, numel(board), t);
    end

    %% Leaderboard: top places as HTML, with the new player highlighted
    function html = boardHtml(pos)
        hex = @(c) sprintf("#%02X%02X%02X", round(c * 255));
        rows = 1:min(LB_SHOW, numel(board));
        if pos > LB_SHOW
            rows = [rows 0 pos];    % 0 = "..." gap, then the player's own place
        end
        html = "<b><span style='color:" + hex(C.gold) + "'>LEADERBOARD</span></b><br>";
        for r = rows
            if r == 0
                html = html + "<span style='color:" + hex(C.text) + "'>...</span><br>";
                continue
            end
            line = sprintf("#%d&nbsp;&nbsp;%s&nbsp;&nbsp;-&nbsp;&nbsp;%.1f s", r, board(r).name, board(r).time);
            if r == pos
                html = html + "<b><span style='color:" + hex(C.glow) + "'>" + line + "&nbsp;&nbsp;&lt;- you</span></b><br>";
            else
                html = html + "<span style='color:" + hex(C.text) + "'>" + line + "</span><br>";
            end
        end
    end

    %% Append one round to round_data.txt
    function logRound(result)
        try
            info = dir(ROUND_LOG);
            newFile = isempty(info) || info.bytes == 0;
            fid = fopen(ROUND_LOG, "a");
            if fid < 0
                error("could not open %s", ROUND_LOG);
            end
            closeFid = onCleanup(@() fclose(fid));
            if newFile
                fprintf(fid, "date_time,result,time_s,threshold_low,threshold_high,avg_accel,peak_accel,samples\n");
            end
            avgAccel = roundSum / max(roundCount, 1);
            fprintf(fid, "%s,%s,%.2f,%.1f,%.1f,%.3f,%.3f,%d\n", ...
                string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")), result, toc(roundTimer), ...
                vibrationThreshold, vibrationMax, avgAccel, roundPeak, roundCount);
            fprintf("Round logged: %s in %.1f s (avg %.2f, peak %.2f)\n", ...
                result, toc(roundTimer), avgAccel, roundPeak);
        catch logErr
            fprintf("Could not log round: %s\n", logErr.message);
        end
    end

    %% Cleanup
    function shutdown()
        if gameState == "playing"
            logRound("quit");
            gameState = "start";
        end
        if ~isempty(PicoObj)
            try
                writeline(PicoObj, "a0");
            catch
            end
            try
                delete(PicoObj);
            catch
            end
        end
        PicoObj = [];
        figs = [fig adminFig];
        delete(figs(isvalid(figs)));
        if isvalid(gameTimer)
            delete(gameTimer);
        end
        fprintf("Olm Cavern closed\n");
    end

end
