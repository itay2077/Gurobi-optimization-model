function PLOT_BUILD_TIMING()
% PLOT_BUILD_TIMING  Effect of the budget on the timing of the transition,
% for a FIXED solar land cap. One window, three stacked panels (x = year):
%   (a) installed solar PV capacity [GW] (solid) and battery power [GW] (dashed)
%   (b) annual life-cycle emissions [MtCO2e]
%   (c) renewable share of generation [%]
% One line per budget. Select the KPI_summary (.mat or .csv) of the run;
% scenario results are read from <run folder>\scenarios\<scenario>\results_heavy.mat

    % ---------------- settings ----------------
    LAND         = 600;                              % km2 (fixed)
    BUDGETS      = [400 410 420 440 480] * 1e9;      % NIS
    SHOW_BATTERY = true;                             % dashed battery lines in panel (a)
    FS           = 14;                               % base font size

    % ---------------- load ----------------
    [K, scenRoot] = local_loadKPI('Select KPI_summary of the run');

    nB   = numel(BUDGETS);
    cols = lines(nB);
    D    = struct('B', {}, 'years', {}, 'sol', {}, 'bat', {}, 'emi', {}, 're', {});
    for k = 1:nB
        j = find(K.MaxAreaSolar == LAND & abs(K.MaxCost - BUDGETS(k)) < 1e6, 1);
        if isempty(j)
            warning('Scenario not found / infeasible: %d km2, %.0f x10^9', LAND, BUDGETS(k)/1e9);
            continue
        end
        f = fullfile(scenRoot, char(string(K.Scenario(j))), 'results_heavy.mat');
        if ~isfile(f), warning('File not found: %s', f); continue; end
        S = load(f, 'RES');  R = S.RES;
        nY  = size(R.genYear, 2);
        G   = R.genYear;                                    % MWh by source x year
        reS = 100 * sum(G([1 2 5], :), 1) ./ max(1, sum(G, 1));   % nuclear + solar + battery discharge
        D(end+1) = struct('B', BUDGETS(k), 'years', R.BaseYear + (0:nY-1), ...
            'sol', R.capYear(2, :) / 1e3, 'bat', R.capYear(5, :) / 1e3, ...
            'emi', R.emitYear(:)' / 1e6, 're', reS); %#ok<AGROW>
    end
    if isempty(D), error('No scenarios found for %d km2.', LAND); end

    % ---------------- window: three panels with identical plot boxes ----------------
    fig = uifigure('Name', sprintf('Build-out timing – %d km2', LAND), ...
                   'Position', [80 40 1280 920], 'Color', 'white');
    L = 110;  W = 1120;  H = 235;          % left edge, width and height of every plot box [px]
    Y = [625 345 65];                      % bottom of panels (a), (b), (c) [px]
    ax = gobjects(3, 1);
    for p = 1:3
        ax(p) = uiaxes(fig, 'Color', 'white');
        ax(p).PositionConstraint = 'innerposition';
        ax(p).InnerPosition      = [L Y(p) W H];
        local_axStyle(ax(p), FS);
        hold(ax(p), 'on');
    end

    % (a) installed capacity
    h = gobjects(numel(D), 1);
    for k = 1:numel(D)
        h(k) = plot(ax(1), D(k).years, D(k).sol, '-', 'Color', cols(k,:), 'LineWidth', 2);
        if SHOW_BATTERY
            plot(ax(1), D(k).years, D(k).bat, '--', 'Color', cols(k,:), 'LineWidth', 1.5);
        end
    end
    ylabel(ax(1), 'Installed capacity [GW]', 'FontWeight', 'bold', 'Color', 'black');
    ttl = sprintf('(a) Installed solar PV capacity%s – land cap %d km^2', ...
        local_if(SHOW_BATTERY, ' (solid) and battery power (dashed)', ''), LAND);
    title(ax(1), ttl, 'FontWeight', 'bold', 'Color', 'black');
    lg = legend(ax(1), h, compose('Budget %.1f ×10^{11} ₪', [D.B]' / 1e11), 'Location', 'northwest');
    lg.Color = 'white';  lg.TextColor = 'black';  lg.FontSize = FS - 2;

    % (b) annual emissions
    for k = 1:numel(D)
        plot(ax(2), D(k).years, D(k).emi, '-', 'Color', cols(k,:), 'LineWidth', 2);
    end
    ylabel(ax(2), 'Emissions [MtCO_2e/yr]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax(2), '(b) Annual life-cycle emissions', 'FontWeight', 'bold', 'Color', 'black');

    % (c) renewable share
    for k = 1:numel(D)
        plot(ax(3), D(k).years, D(k).re, '-', 'Color', cols(k,:), 'LineWidth', 2);
    end
    ylabel(ax(3), 'Renewable share [%]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax(3), '(c) Renewable share of generation', 'FontWeight', 'bold', 'Color', 'black');
    xlabel(ax(3), 'Year', 'FontWeight', 'bold', 'Color', 'black');

    % identical x-axis in all panels
    yrs = [min([D.years]) max([D.years])];
    for p = 1:3
        xlim(ax(p), yrs);
        xticks(ax(p), yrs(1):3:yrs(2));
        ax(p).InnerPosition = [L Y(p) W H];   % re-apply after labels/titles were added
    end
    linkaxes(ax, 'x');

    % ---------------- print key numbers ----------------
    fprintf('\n=== Build-out timing, land cap %d km2 ===\n', LAND);
    fprintf('%8s | %10s %10s | %12s %12s | %8s\n', 'Budget', 'Solar2035', 'Solar2050', 'Emis2035', 'CumEmis', 'RE2035');
    for k = 1:numel(D)
        i35 = find(D(k).years == 2035, 1);
        fprintf('%8.0f | %10.1f %10.1f | %12.1f %12.0f | %8.1f\n', D(k).B/1e9, ...
            D(k).sol(i35), D(k).sol(end), D(k).emi(i35), sum(D(k).emi), D(k).re(i35));
    end
    fprintf('(capacity in GW, emissions in MtCO2e)\n\n');
end

% =========================================================================
function [K, scenRoot] = local_loadKPI(promptStr)
    [f, p] = uigetfile({'*.mat;*.csv', 'KPI summary (*.mat, *.csv)'}, promptStr);
    if isequal(f, 0), error('No file selected.'); end
    file = fullfile(p, f);
    [~, ~, ext] = fileparts(file);
    if strcmpi(ext, '.mat')
        S = load(file, 'KPI');  K = S.KPI;
    else
        K = readtable(file);
    end
    K = K(string(K.ResultStatus) == "OPTIMAL", :);
    runDir   = fileparts(fileparts(file));
    scenRoot = fullfile(runDir, 'scenarios');
    if ~isfolder(scenRoot)
        scenRoot = uigetdir(runDir, 'Select the "scenarios" folder');
    end
end

function local_axStyle(ax, FS)
    ax.Color     = 'white';
    ax.XColor    = 'black';  ax.YColor = 'black';
    ax.GridColor = [0.15 0.15 0.15];
    ax.FontSize  = FS - 2;
    ax.LineWidth = 1;
    ax.Box       = 'on';
    grid(ax, 'on');
end

function out = local_if(c, a, b)
    if c, out = a; else, out = b; end
end
