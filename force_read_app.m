% test changes

function force_read_app()
    % Configuration  
    deviceName = "Force_Sensor_1"; 
    serviceUUID = "181D"; 
    characteristicUUID = "2A9D";

    % Build the figure and UI 
    fig = uifigure('Name', 'Force Sensor Live Monitor', 'Position', [100 100 640 480], ...
        'CloseRequestFcn', @(~,~) closeApp());

    % Tab Group
    tabGroup = uitabgroup(fig, 'Position', [1 1 640 480]);
    plotTab = uitab(tabGroup, 'Title', 'Plot');
    dataTableTab = uitab(tabGroup, 'Title', 'Data Table');

    % Axes for Live Plot
    ax = uiaxes(plotTab, 'Position', [39 49 388 389]);
    title(ax, 'Live Sensor Reading');
    xlabel(ax, 'Time (s)');
    ylabel(ax, 'Value');
    grid(ax, 'on');

    hLine1 = animatedline(ax, 'Color', '#0072BD', 'LineWidth', 1.5, 'DisplayName', 'Raw (mV)');
    hLine2 = animatedline(ax, 'Color', '#D9531F', 'LineWidth', 1.5, 'DisplayName', 'Weight (g)');
    hLine3 = animatedline(ax, 'Color', '#7E2F8E', 'LineWidth', 1.5, 'DisplayName', 'Force (N)');
    legend(ax, 'show');

    % Data Table UI
    uit = uitable(dataTableTab, 'Position', [38 57 388 371], ...
        'ColumnName', {'Time (s)', 'Raw (mV)', 'Weight (g)', 'Force (N)'}, ...
        'RowName', {});

    % Control Panel (Toggles & Buttons)
    panel = uipanel(plotTab, 'Title', 'Values', 'TitlePosition', 'centertop', 'Position', [465 58 147 371]);

    % Data Storage Arrays & Control Flags
    timeData = []; rawData = []; weightData = []; forceData = [];
    isAcquiring = false;
    bleDev = [];
    bleChar = [];

    % Creating UI components 

    % Raw Values Toggle
    uilabel(panel, 'HorizontalAlignment', 'center', 'Position', [43 310 62 22], 'Text', 'raw values');
    rawToggle = uibutton(panel, 'state', 'Position', [34 280 80 25], ...
        'Text', 'Raw', 'Value', true, ...
        'BackgroundColor', [0.4 0.8 0.4], ...
        'ValueChangedFcn', @(s,~) setToggleState(s, hLine1));

    % Weight Values Toggle
    uilabel(panel, 'HorizontalAlignment', 'center', 'Position', [34 225 81 22], 'Text', 'weight values');
    weightToggle = uibutton(panel, 'state', 'Position', [34 195 80 25], ...
        'Text', 'Weight', 'Value', true, ...
        'BackgroundColor', [0.4 0.8 0.4], ...
        'ValueChangedFcn', @(s,~) setToggleState(s, hLine2));

    % Force Values Toggle
    uilabel(panel, 'HorizontalAlignment', 'center', 'Position', [40 140 70 22], 'Text', 'force values');
    forceToggle = uibutton(panel, 'state', 'Position', [34 110 80 25], ...
        'Text', 'Force', 'Value', true, ...
        'BackgroundColor', [0.4 0.8 0.4], ...
        'ValueChangedFcn', @(s,~) setToggleState(s, hLine3));

    % Start / Stop Button
    startStopBtn = uibutton(panel, 'push', 'Position', [24 65 100 25], ...
        'Text', 'Start', ...
        'BackgroundColor', [0.8 0.9 0.8], ...
        'ButtonPushedFcn', @(~,~) toggleAcquisition());

    % Clear Data Button
    uibutton(panel, 'push', 'Position', [24 30 100 25], ...
        'Text', 'Clear Data', ...
        'ButtonPushedFcn', @(~,~) clearData());

    % Close Button
    uibutton(plotTab, 'push', 'Position', [529 9 100 23], ...
        'Text', 'Close', ...
        'ButtonPushedFcn', @(~,~) closeApp());

    % Set initial line visibilities
    setToggleState(rawToggle, hLine1);
    setToggleState(weightToggle, hLine2);
    setToggleState(forceToggle, hLine3);

    % --- BACKGROUND ACQUISITION LOOP ---
    while isvalid(fig)
        if isAcquiring && ~isempty(bleChar)
            try
                % PULL IN HERE 
                % put all this into the separate/background function
                rawBytes = read(bleChar);
                %disp(length(rawBytes));
                if length(rawBytes) == 17
                    raw_mV   = typecast(uint8(rawBytes(1:4)), 'single');
                    weight_g = typecast(uint8(rawBytes(5:8)), 'single');
                    force_N  = typecast(uint8(rawBytes(9:12)), 'single');
                    time_ms  = typecast(uint8(rawBytes(13:16)), 'uint32');

                    tSec = double(time_ms) / 1000.0;

                    % Append data
                    timeData(end+1)   = tSec;
                    rawData(end+1)    = double(raw_mV);
                    weightData(end+1) = double(weight_g);
                    forceData(end+1)  = double(force_N);

                    % Update plot lines
                    addpoints(hLine1, tSec, double(raw_mV));
                    addpoints(hLine2, tSec, double(weight_g));
                    addpoints(hLine3, tSec, double(force_N));

                    drawnow limitrate;

                    % Update table (showing last 100 rows)
                    idx = max(1, length(timeData) - 100);
                    uit.Data = table(timeData(idx:end)', rawData(idx:end)', weightData(idx:end)', forceData(idx:end)', ...
                        'VariableNames', {'Time (s)', 'Raw (mV)', 'Weight (g)', 'Force (N)'});
                end
            catch
                % Suppress minor dropouts during streaming
            end
        end
        pause(0.01); 
    end


    % --- HELPER FUNCTIONS ---

    function setToggleState(btn, lineObj)
        if btn.Value
            lineObj.Visible = 'on';
            btn.BackgroundColor = [0.4 0.8 0.4]; % Green
        else
            lineObj.Visible = 'off';
            btn.BackgroundColor = [0.8 0.8 0.8]; % Grey
        end
    end

    function toggleAcquisition()
        if ~isAcquiring
            disp('Connecting to BLE Device...');
            try
                bleDev = ble(deviceName);
                bleChar = characteristic(bleDev, serviceUUID, characteristicUUID);
                isAcquiring = true;
                startStopBtn.Text = 'Stop';
                startStopBtn.BackgroundColor = [0.9 0.4 0.4]; 
                disp('Connected and streaming data!');
            catch ME
                uialert(fig, ME.message, "BLE Connection Error");
                isAcquiring = false;
            end
        else
            isAcquiring = false;
            clear bleChar bleDev;
            startStopBtn.Text = 'Start';
            startStopBtn.BackgroundColor = [0.8 0.9 0.8];
            disp('Acquisition stopped.');
        end
    end

    function clearData()
        timeData = []; rawData = []; weightData = []; forceData = [];
        clearpoints(hLine1); clearpoints(hLine2); clearpoints(hLine3);
        uit.Data = table();
    end

    function closeApp()
        isAcquiring = false;
        clear bleChar bleDev;
        delete(fig);
    end
end
