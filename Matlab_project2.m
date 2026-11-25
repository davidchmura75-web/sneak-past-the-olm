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
ROUND_LOG = fullfile(fileparts(mfilename("fullpath")), "round_data.txt");
LEADERBOARD = fullfile(fileparts(mfilename("fullpath")), "leaderboard.txt");
CAUGHT_SOUND = fullfile(fileparts(mfilename("fullpath")), "olm_caught.wav");
G = 9.81;           % 1g = shorted sensor
SHORT_TOL = 0.05;   % 1g tolerance
SHORT_WIN = 100;    % readings checked
SHORT_HITS = 10;    % 1g readings = shorting
LB_SHOW = 5;        % leaderboard places
B2B_GAP = 20;       % back to back gap (s)
NUM_EVENTS = 3;     % secret spots
SPOT_BONUS = 10;    % seconds off per spot
SMOOTH_N = 6;       % readings averaged
WARN_PCT = 70;      % warning at %
WARN_HOLD = 3;      % warning hold (s)
LEAVE_GRACE = 1;    % spot leave delay (s)
CHECK = char(10004);
CROSS = "X";

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
sg = uigridlayout(sensPnl, [12 2], ...
    "RowHeight", {28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 48, '1x'}, ...
    "ColumnWidth", {28, '1x'}, "Padding", 12, "RowSpacing", 6, ...
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

% Special event beam lamps (rows 3-5)
eventLamps = gobjects(1, NUM_EVENTS);
eventLbls  = gobjects(1, NUM_EVENTS);
eventHits  = zeros(1, NUM_EVENTS);   % times each event fired this session
for e = 1:NUM_EVENTS
    eventLamps(e) = uilamp(sg, "Color", C.glow);
    eventLamps(e).Layout.Row = 2 + e; eventLamps(e).Layout.Column = 1;
    eventLbls(e) = uilabel(sg, "Text", sprintf("Event %d Beam: clear", e), ...
        "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
    eventLbls(e).Layout.Row = 2 + e; eventLbls(e).Layout.Column = 2;
end

% Start button
btnLbl = uilabel(sg, "Text", "Start Button: not pressed", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
btnLbl.Layout.Row = 6; btnLbl.Layout.Column = [1 2];
btnPresses = 0;

% Readouts
vibLbl = uilabel(sg, "Text", "Accelerometer: --", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
vibLbl.Layout.Row = 7; vibLbl.Layout.Column = [1 2];
stateLbl = uilabel(sg, "Text", "Game State: start", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.gold);
stateLbl.Layout.Row = 8; stateLbl.Layout.Column = [1 2];
idleLbl = uilabel(sg, "Text", "Idle: 0 s", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
idleLbl.Layout.Row = 9; idleLbl.Layout.Column = [1 2];
servoLbl = uilabel(sg, "Text", "Servo: --", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text);
servoLbl.Layout.Row = 10; servoLbl.Layout.Column = [1 2];

% Accelerometer wiring check (admin only) - stuck at 1g means shorted/disconnected
wireLamp = uilamp(sg, "Color", C.glow);
wireLamp.Layout.Row = 11; wireLamp.Layout.Column = 1;
wireLbl = uilabel(sg, "Text", "Accel wiring: waiting for data", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.text, "WordWrap", "on");
wireLbl.Layout.Row = 11; wireLbl.Layout.Column = 2;

% Sensitivity slider
sldLbl = uilabel(aRoot, "Text", "Adjust Accelerometer Sensitivity!", ...
    "FontSize", 16, "FontWeight", "bold", "FontColor", C.gold);
sldLbl.Layout.Row = 3; sldLbl.Layout.Column = [1 2];

sld = uislider(aRoot, "range");
sld.Layout.Row = 4; sld.Layout.Column = [1 2];
sld.Step = 0.1;
sld.Limits = [0 40];
sld.MajorTicks = 0:2:40;                         % a number every 2, all the way across
sld.MajorTickLabels = string(sld.MajorTicks);
sld.MinorTicks = 0:0.5:40;
sld.Value = [1 5];                               % starting sensitivity range
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

% Special event pages - shown while a special beam (B4/B5/B6) is broken during a
% round, and gone the instant the part leaves it. Each spot takes SPOT_BONUS seconds
% off the round time (once per spot per round). Extra effects go in onSpecialEvent().
evBg    = [0.10 0.05 0.25; 0.02 0.18 0.22; 0.20 0.12 0.02];
evTitle = ["Secret Spot 1", "Secret Spot 2", "Secret Spot 3"];
evColor = [C.gold; C.aqua; C.glow];
evImg   = ["olm_drawing_4am.png", "confused_olm.png", "alert_olm.png"];
evSub   = repmat(sprintf("You found a secret spot!  -%d seconds off your time", SPOT_BONUS), 1, 3);

scrBg    = [scrBg; evBg];
scrTitle = [scrTitle evTitle];
scrColor = [scrColor; evColor];
scrImg   = [scrImg evImg];
scrSub   = [scrSub evSub];
NUM_SCR  = numel(scrTitle);    % 4 base screens + special events (screen 4 + e = event e)

gauges  = gobjects(2, 1);
titles  = gobjects(2, 1);
screens = gobjects(2, NUM_SCR);
bigLbls = gobjects(2, NUM_SCR);
subLbls = gobjects(2, NUM_SCR);
hints   = gobjects(2, NUM_SCR);
lbLbls  = gobjects(2, 1);   % leaderboard on the win screen
instrLbls = gobjects(2, 1); % how-to-play instructions on the gameplay page
dialLbls  = gobjects(2, 1); % what the gauge means
warnLbls  = gobjects(2, 1); % "the olm feels your vibrations" warning

for k = 1:2
    grid = uigridlayout(parents{k}, [5 4], ...
        "RowHeight", {'0.03x', '0.1x', '1x', '0.18x', '0.03x'}, ...
        "ColumnWidth", {'0.02x', '1.3x', '1x', '0.02x'}, ...
        "Padding", 0, "RowSpacing", 6, "ColumnSpacing", 12, ...
        "BackgroundColor", C.abyss);

    titles(k) = uilabel(grid, "Text", "OLM CAVERN  -  Vibration Detection", ...
        "FontName", FONT, "FontSize", 28, "FontWeight", "bold", "FontColor", C.aqua);
    titles(k).Layout.Row = 2; titles(k).Layout.Column = [2 3];

    % Drawn by me fr
    img = uiimage(grid, "ImageSource", "olm_image.png");
    img.Layout.Row = 3; img.Layout.Column = 2;

    % Vibration gauge, with a label saying what it is and a warning underneath
    gaugeCol = uigridlayout(grid, [3 1], "RowHeight", {'0.22x', '1x', '0.22x'}, ...
        "ColumnWidth", {'1x'}, "Padding", 0, "RowSpacing", 4, "BackgroundColor", C.abyss);
    gaugeCol.Layout.Row = 3; gaugeCol.Layout.Column = 3;

    dialLbls(k) = uilabel(gaugeCol, "Text", sprintf("OLM ALERT METER\nHits 100%% = the olm wakes up"), ...
        "FontName", FONT, "FontSize", 18, "FontWeight", "bold", "FontColor", C.gold, ...
        "HorizontalAlignment", "center", "VerticalAlignment", "bottom", "WordWrap", "on");
    dialLbls(k).Layout.Row = 1;

    gauges(k) = uigauge(gaugeCol, ...
        "BackgroundColor", C.card, "FontColor", C.text, ...
        "ScaleColors", [C.glow; C.gold; C.coral], ...
        "ScaleColorLimits", [0 60; 60 80; 80 100]);
    gauges(k).Layout.Row = 2;

    warnLbls(k) = uilabel(gaugeCol, "Text", "The olm feels your vibrations!", ...
        "FontName", FONT, "FontSize", 18, "FontWeight", "bold", "FontColor", C.coral, ...
        "HorizontalAlignment", "center", "VerticalAlignment", "top", "WordWrap", "on", ...
        "Visible", "off");
    warnLbls(k).Layout.Row = 3;

    % How to play
    instrLbls(k) = uilabel(grid, "Text", sprintf( ...
        "Sneak the prey past the olm to the end of the cave without waking it up.\n" + ...
        "Find the 3 secret spots on the way - each one takes %d seconds off your time!", SPOT_BONUS), ...
        "FontName", FONT, "FontSize", 18, "FontColor", C.text, ...
        "HorizontalAlignment", "center", "WordWrap", "on");
    instrLbls(k).Layout.Row = 4; instrLbls(k).Layout.Column = [2 3];

    % Full-page overlays
    for s = 1:NUM_SCR
        pnl = uipanel(grid, "BorderType", "none", "BackgroundColor", scrBg(s,:));
        pnl.Layout.Row = [1 5]; pnl.Layout.Column = [1 4];

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
servoSent = -1;         % -1 = not sent
servoConfirmed = -1;    % -1 = unknown
lastServoSend = tic;
activeEvent = 0;        % 0 = none
spotsFound = false(1, NUM_EVENTS);
warnOn = false;
lastWarn = tic;
eventLeaving = false;
leaveTimer = tic;

vibes = 0.0;
vibPct = 0.0;           % 0-100
history = zeros(1, SMOOTH_N);

vibrationThreshold = 1.0;
vibrationMax = 5.0;

% Round stats
roundTimer = tic;
roundSum = 0;
roundCount = 0;
roundPeak = 0;

% Leaderboard
board = loadBoard();

% Short detection
stuckHist = false(1, SHORT_WIN);
shorting = false;

% Caught sound
caughtPlayer = makeCaughtPlayer();

% Back to back
lastRoundEnd = lastLoggedEnd();
backToBack = false;

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
                titles(n).FontSize = max(10, round(h * 0.04));
                instrLbls(n).FontSize = max(9, round(h * 0.03) + 2);    % instructions 2 sizes bigger
                set([dialLbls(n) warnLbls(n)], "FontSize", max(6, round(h * 0.03) - 2));
            end
        end
        lastHeights = heights;

        % Show screen for state
        set(screens(:,1), "Visible", gameState == "start");
        set(screens(:,2), "Visible", gameState == "win");
        set(screens(:,3), "Visible", gameState == "lose");
        set(screens(:,4), "Visible", isempty(PicoObj));

        % Start screen title says "Move to start" until the prey is on the start beam
        if startBeamOn
            set(bigLbls(:,1), "Text", "Start");
            set(subLbls(:,1), "Text", "Press the start button to dive into the cavern");
        else
            set(bigLbls(:,1), "Text", "Move to start");
            set(subLbls(:,1), "Text", "Move the prey to the start line");
        end
        set(hints(:,1), "Visible", "off");

        % Win/lose screens: how to reset
        if startBeamOn
            set(hints(:,2:3), "Text", "Press the start button to play again");
        else
            set(hints(:,2:3), "Text", "Bring the prey back to the start to reset");
        end

        % "The olm feels your vibrations" - stays WARN_HOLD seconds after the meter drops
        if warnOn && (gameState ~= "playing" || toc(lastWarn) > WARN_HOLD)
            warnOn = false;
        end
        set(warnLbls, "Visible", warnOn);

        % Special event pages stay up only while the part is on that spot's beam
        % (they're cleared the moment the beam reports clear, or if the round ended)
        if activeEvent > 0 && (gameState ~= "playing" || ...
                (eventLeaving && toc(leaveTimer) > LEAVE_GRACE))
            activeEvent = 0;
            eventLeaving = false;
        end
        for ev = 1:NUM_EVENTS
            set(screens(:,4+ev), "Visible", activeEvent == ev);
        end

        % Admin readouts
        stateLbl.Text = "Game State: " + gameState;
        if gameState == "playing"
            stateLbl.Text = stateLbl.Text + sprintf(" (spots %d/%d)", nnz(spotsFound), NUM_EVENTS);
        end
        if activeEvent > 0
            stateLbl.Text = stateLbl.Text + sprintf(" - on spot %d", activeEvent);
            if eventLeaving
                stateLbl.Text = stateLbl.Text + " (leaving)";
            end
        end
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
                    if ~isscalar(vibes) || ~isfinite(vibes)
                        continue
                    end
                    if vibes < vibrationThreshold
                        vibPct = 0;
                    elseif vibes > vibrationMax
                        vibPct = 100;
                    else
                        vibPct = (((vibes - vibrationThreshold) / (vibrationMax - vibrationThreshold)) * 100.0);
                    end

                    history = [history(2:end) vibPct];
                    gaugeVal = mean(history);
                    set(gauges, "Value", gaugeVal);
                    vibLbl.Text = sprintf("Accelerometer: %.2f", vibes);
                    checkShort(vibes);

                    % Round stats
                    if gameState == "playing"
                        roundSum = roundSum + vibes;
                        roundCount = roundCount + 1;
                        roundPeak = max(roundPeak, vibes);
                        if gaugeVal >= WARN_PCT
                            warnOn = true;
                            lastWarn = tic;
                        end
                    end

                    % Too much vibration
                    if gameState == "playing" && gaugeVal >= 100
                        gameState = "lose";
                        lastActivity = tic;   % start idle countdown on lose screen
                        playCaught();
                        logRound("lose");
                    end

                elseif startsWith(PicoMsg, 'B1:')
                    % Start button
                    btnPresses = btnPresses + 1;
                    btnLbl.Text = sprintf("Start Button: pressed (%d)", btnPresses);
                    lastActivity = tic;

                    if gameState == "start" && startBeamOn
                        gameState = "playing";
                        history = zeros(1, SMOOTH_N);
                        roundTimer = tic;
                        % Back to back: started less than B2B_GAP s after the last round ended
                        downTime = seconds(datetime("now") - lastRoundEnd);
                        backToBack = ~isnan(downTime) && downTime < B2B_GAP;
                        if ~isnan(downTime)
                            fprintf("Round started %.1f s after the last one%s\n", downTime, ...
                                string(repmat(' (back to back)', 1, backToBack)));
                        end
                        roundSum = 0;
                        roundCount = 0;
                        roundPeak = 0;
                        spotsFound = false(1, NUM_EVENTS);
                        activeEvent = 0;
                        eventLeaving = false;
                        warnOn = false;
                    elseif gameState == "win" || gameState == "lose"
                        gameState = "start";
                    end

                elseif startsWith(PicoMsg, 'B2:')
                    % Start beam
                    beamVal = sscanf(PicoMsg, 'B2:%d');
                    if ~isscalar(beamVal)
                        continue    % garbled message
                    end
                    wasOnStart = startBeamOn;
                    startBeamOn = beamVal == 1;
                    if startBeamOn
                        startLamp.Color = C.coral;
                        startLbl.Text = "Start Beam: part on";
                        % Prey brought back to the start after a round - reset to the start screen
                        if ~wasOnStart && (gameState == "win" || gameState == "lose")
                            gameState = "start";
                            lastActivity = tic;
                        end
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
                            activeEvent = 0;
                        end
                    else
                        endLamp.Color = C.glow;
                        endLbl.Text = "End Beam: clear";
                    end

                elseif startsWith(PicoMsg, ["B4:", "B5:", "B6:"])
                    % Special event beams (B4 = event 1, B5 = event 2, B6 = event 3)
                    vals = sscanf(PicoMsg, 'B%d:%d');
                    if numel(vals) ~= 2
                        continue    % garbled message
                    end
                    evNum = vals(1) - 3;
                    if vals(2) == 1
                        eventLamps(evNum).Color = C.coral;
                        eventLbls(evNum).Text = sprintf("Event %d Beam: part on", evNum);
                        if activeEvent == evNum
                            eventLeaving = false;   % beam flickered - still on the spot
                        elseif gameState == "playing" && ~spotsFound(evNum)
                            startSpecialEvent(evNum);   % each spot only counts once per round
                        end
                    else
                        eventLamps(evNum).Color = C.glow;
                        eventLbls(evNum).Text = sprintf("Event %d Beam: clear", evNum);
                        if activeEvent == evNum && ~eventLeaving
                            eventLeaving = true;    % back to the cave if it stays clear for LEAVE_GRACE
                            leaveTimer = tic;
                        end
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
            vibPct = 0;
            history = zeros(1, SMOOTH_N);
            set(gauges, "Value", 0);
            vibLbl.Text = "Accelerometer: --";
            stuckHist = false(1, SHORT_WIN);
            shorting = false;
            wireLamp.Color = C.glow;
            set(wireLbl, "Text", "Accel wiring: waiting for data", "FontColor", C.text);
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
            history = zeros(1, SMOOTH_N);
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

    %% Leaderboard: read leaderboard.txt (name,time_s,date_time,spots,back_to_back)
    % time_s already has the secret spot bonus taken off; spots is e.g. "101"
    % (spot 1 and 3 found); back_to_back is 1 if the run started less than B2B_GAP
    % seconds after the previous round ended. Older lines missing columns still load.
    function b = loadBoard()
        b = struct("name", {}, "time", {}, "date", {}, "spots", {}, "b2b", {});
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
                spots = "";
                if numel(parts) >= 4
                    spots = parts(4);
                end
                b2b = numel(parts) >= 5 && parts(5) == "1";
                b(end+1) = struct("name", parts(1), "time", t, "date", parts(3), ...
                    "spots", spots, "b2b", b2b); %#ok<AGROW>
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
                 "Hushed", "Misty", "Velvet", "Sleepy", "Soft-Step", "Careful", "Ghostly", ...
                 "Sly", "Nimble", "Feathery", "Whispering", "Murky", "Dusky", "Shy", ...
                 "Cunning", "Slippery", "Tranquil", "Drowsy", "Patient", "Graceful", "Mossy", ...
                 "Glowing", "Damp", "Echoing", "Hidden", "Lurking", "Crafty", "Wary", ...
                 "Featherfoot", "Muffled", "Twilight", "Murmuring", "Delicate", "Steady", "Calm"];
        nouns = ["Olm", "Gecko", "Newt", "Bat", "Shrimp", "Crayfish", "Salamander", ...
                 "Glowworm", "Cavefish", "Spelunker", "Pebble", "Axolotl", "Beetle", "Mole", ...
                 "Stalactite", "Stalagmite", "Cricket", "Spider", "Millipede", "Centipede", "Snail", ...
                 "Moth", "Toad", "Frog", "Isopod", "Worm", "Crystal", "Geode", ...
                 "Mushroom", "Lantern", "Explorer", "Miner", "Diver", "Ripple", "Puddle", ...
                 "Owl", "Fox", "Ferret", "Hedgehog", "Bubble", "Echo", "Pixie"];
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
    function addWinner(rawTime)
        bonus = SPOT_BONUS * nnz(spotsFound);
        t = max(0, rawTime - bonus);
        name = makeName();
        board(end+1) = struct("name", name, "time", t, ...
            "date", string(datetime("now", "Format", "yyyy-MM-dd HH:mm:ss")), ...
            "spots", string(char('0' + spotsFound)), "b2b", backToBack);
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
            fprintf(fid, "name,time_s,date_time,spots,back_to_back\n");
            for i = 1:numel(board)
                fprintf(fid, "%s,%.2f,%s,%s,%d\n", board(i).name, board(i).time, board(i).date, ...
                    board(i).spots, board(i).b2b);
            end
            clear closeFid
        catch lbErr
            fprintf("Could not save leaderboard: %s\n", lbErr.message);
        end

        % Win screen text
        if bonus > 0
            timeTxt = sprintf("%.1f s  -  %.1f s raw, -%d s bonus", t, rawTime, bonus);
        else
            timeTxt = sprintf("%.1f s", t);
        end
        set(subLbls(:,2), "Text", sprintf("You are %s  -  #%d of %d  (%s)", ...
            name, pos, numel(board), timeTxt));
        set(lbLbls, "Text", boardHtml(pos));
        fprintf("Leaderboard: %s placed #%d of %d with %.2f s (%.2f raw, spots %s%s)\n", ...
            name, pos, numel(board), t, rawTime, board(pos).spots, ...
            string(repmat(', back to back', 1, backToBack)));
    end

    %% Three checkmarks: green for a found spot, dim for a missed one
    function html = checksHtml(spots, sz)
        html = "";
        spots = char(spots);
        if numel(spots) ~= NUM_EVENTS
            spots = repmat('0', 1, NUM_EVENTS);  % old entry from before spots were tracked - all X
        end
        for i = 1:NUM_EVENTS
            if spots(i) == '1'
                col = "#33FF66";    % bright green check = found
                mark = CHECK;
            else
                col = "#FF1F1F";    % bright red X = missed
                mark = CROSS;
            end
            html = html + "<span style='color:" + col + ";font-size:" + sz + "'>" + mark + "</span>&nbsp;";
        end
    end

    function h = hexColor(c)
        h = sprintf("#%02X%02X%02X", round(c * 255));
    end

    %% Leaderboard: this round's checkmarks, then top places as HTML, with the new player highlighted
    function html = boardHtml(pos)
        hex = @hexColor;
        rows = 1:min(LB_SHOW, numel(board));
        if pos > LB_SHOW
            rows = [rows 0 pos];    % 0 = "..." gap, then the player's own place
        end
        found = nnz(char(board(pos).spots) == '1');
        html = "<b><span style='color:" + hex(C.gold) + ";font-size:150%'>SECRET SPOTS</span>" + ...
            sprintf("<span style='color:%s;font-size:150%%'>&nbsp;&nbsp;%d of %d found</span><br>", ...
                hex(C.text), found, NUM_EVENTS) + ...
            checksHtml(board(pos).spots, "320%") + "</b><br><br>";
        html = html + "<b><span style='color:" + hex(C.gold) + "'>LEADERBOARD</span></b><br>";
        anyB2B = false;
        for r = rows
            if r == 0
                html = html + "<span style='color:" + hex(C.text) + "'>...</span><br>";
                continue
            end
            line = sprintf("#%d&nbsp;&nbsp;%s&nbsp;&nbsp;-&nbsp;&nbsp;%.1f s&nbsp;&nbsp;", r, board(r).name, board(r).time);
            checks = checksHtml(board(r).spots, "100%");
            if board(r).b2b
                checks = checks + "<span style='color:" + hex(C.gold) + "'>&nbsp;B2B</span>";
                anyB2B = true;
            end
            if r == pos
                html = html + "<b><span style='color:" + hex(C.glow) + "'>" + line + "</span>" + checks + ...
                    "<span style='color:" + hex(C.glow) + "'>&nbsp;&lt;- you</span></b><br>";
            else
                html = html + "<span style='color:" + hex(C.text) + "'>" + line + "</span>" + checks + "<br>";
            end
        end
        if anyB2B
            html = html + sprintf("<span style='color:%s;font-size:75%%'>B2B = back to back (started under %d s after the last round)</span>", ...
                hex(C.gold), B2B_GAP);
        end
    end

    %% Special events: show the event page and run its effect
    % Only called the first time a spot is found each round
    function startSpecialEvent(n)
        activeEvent = n;
        eventLeaving = false;
        spotsFound(n) = true;
        eventHits(n) = eventHits(n) + 1;
        set(hints(:,4+n), "Text", sprintf("Spots found: %d of %d  -  leave the spot to go back to the cave", ...
            nnz(spotsFound), NUM_EVENTS));
        fprintf("Special event %d triggered (%.1f s into the round, %d total)\n", ...
            n, toc(roundTimer), eventHits(n));
        onSpecialEvent(n);
    end

    %% Special events: put any extra effect for each spot here
    % Runs the first time the spot's beam is broken each round (the SPOT_BONUS time bonus is
    % already handled above). The page text/image lives in the "Special event pages"
    % section near the top. Examples of things
    % you can change from here: roundTimer, vibrationThreshold/vibrationMax (sld.Value),
    % history (the gauge), gameState, or send the Pico a command with writeline(PicoObj, ...).
    function onSpecialEvent(n)
        switch n
            case 1
                % TODO: special event 1 effect
            case 2
                % TODO: special event 2 effect
            case 3
                % TODO: special event 3 effect
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
        lastRoundEnd = datetime("now");     % for spotting back-to-back runs
    end

    %% Accelerometer short check (admin screen only)
    % A shorted or disconnected ADXL345 reads x = y = z = 0, and the Pico's formula
    % turns that into exactly 1g. Normal readings are ~0 at rest, so lots of readings
    % sitting at 1g means the wiring is shorting.
    function checkShort(v)
        stuckHist = [stuckHist(2:end) abs(v - G) < SHORT_TOL];
        hits = nnz(stuckHist);
        wasShorting = shorting;
        shorting = hits >= SHORT_HITS;
        if shorting
            wireLamp.Color = C.coral;
            set(wireLbl, "Text", sprintf("Accel SHORTING? stuck at 1g (%d of last %d) - check wiring", ...
                hits, SHORT_WIN), "FontColor", C.coral);
            if ~wasShorting
                fprintf("Accelerometer looks shorted - %d of the last %d readings stuck at 1g\n", hits, SHORT_WIN);
            end
        else
            wireLamp.Color = C.glow;
            set(wireLbl, "Text", "Accel wiring: OK", "FontColor", C.text);
            if wasShorting
                fprintf("Accelerometer readings back to normal\n");
            end
        end
    end

    %% "Olm caught you" sound
    % Loads CAUGHT_SOUND. If the file doesn't exist yet, writes a placeholder growl
    % to it first - replace olm_caught.wav with any .wav to change the sound.
    function p = makeCaughtPlayer()
        p = [];
        try
            if ~isfile(CAUGHT_SOUND)
                fs = 44100;
                t = (0:1/fs:1.2)';
                f = 220 * exp(-1.6 * t);                    % pitch sweeps down
                tone = sin(2*pi*cumsum(f)/fs) + 0.5 * sin(2*pi*cumsum(f/2)/fs);
                growl = 0.35 * randn(size(t)) .* (0.5 + 0.5 * sin(2*pi*30*t));
                env = min(1, t / 0.05) .* exp(-1.5 * t);    % quick attack, slow fade
                y = (tone + growl) .* env;
                y = 0.9 * y / max(abs(y));
                audiowrite(CAUGHT_SOUND, y, fs);
                fprintf("Wrote placeholder sound %s\n", CAUGHT_SOUND);
            end
            [y, fs] = audioread(CAUGHT_SOUND);
            p = audioplayer(y, fs);
        catch sndErr
            fprintf("Caught sound unavailable: %s\n", sndErr.message);
        end
    end

    function playCaught()
        try
            if ~isempty(caughtPlayer)
                stop(caughtPlayer);
                play(caughtPlayer);
            end
        catch sndErr
            fprintf("Could not play caught sound: %s\n", sndErr.message);
        end
    end

    %% When the last round in round_data.txt ended (so back to back works across restarts)
    function t = lastLoggedEnd()
        t = NaT;
        try
            lines = readlines(ROUND_LOG, "EmptyLineRule", "skip");
            if numel(lines) > 1
                t = datetime(extractBefore(lines(end), ","), "InputFormat", "yyyy-MM-dd HH:mm:ss");
            end
        catch
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
