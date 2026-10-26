%% ============================================================
%  OPT_ONE_ANALYSIS_DASHBOARD.m
% ============================================================
clear; clc; close all;

% 1. Initialization Function
% Load base data (demand, CF, emission factors, color palette)
globalData = INITIALIZE_DATA();

%% 2. Select SUMMARY Sheet / File
% Select KPI_summary file (.mat or .csv)
[KPI_Data, scenRoot, fullKpiFile] = SELECT_SUMMARY_FILE();
%%
% 3. SUMMARY Analysis
% Open a single UI window with tabs allowing navigation through summary graphs for all scenarios
ANALYZE_SUMMARY_UI(KPI_Data, scenRoot, globalData);

%% 4. Select Specific Scenario
% Select a specific scenario from the KPI table using a UI list dialog
selectedScenarioName = SELECT_SPECIFIC_SCENARIO(KPI_Data);

% 5. Specific Scenario Analysis
% Open a single UI window for the selected scenario, including the interactive drill-down generation mix
if ~isempty(selectedScenarioName)
    ANALYZE_SPECIFIC_SCENARIO_UI(selectedScenarioName, scenRoot, globalData, KPI_Data);
end
%% 6. Select 12 Representative Scenarios (Pareto / Efficiency Frontier)
% Select exactly 12 scenarios representing the most cost-efficient pathways 
% across the entire spectrum of renewable energy penetration.
if exist('KPI_Data', 'var')
    rep12_KPI = SELECT_12_REPRESENTATIVE_SCENARIOS(KPI_Data);
else
    warning('KPI_Data not found. Please run the Initialization and Summary blocks first.');
end
% 7. Analyze 12 Representative Scenarios (Dashboard)
% Open a specific UI dashboard for the 12 selected Pareto scenarios
if exist('rep12_KPI', 'var') && height(rep12_KPI) > 0
    ANALYZE_12_REPRESENTATIVE_UI(rep12_KPI, scenRoot, globalData);
end

%% ============================================================
%  LOCAL FUNCTIONS
% ============================================================

function globalData = INITIALIZE_DATA()
    % This function loads the main Excel file and centralizes base data,
    % avoiding the need to reload it for every generated plot.
    
    fprintf('Initializing base data...\n');
    
    % Hardcoded path to the Excel file
    MP = machine_paths();  xlsFile = MP.xlsFile; sheetName = 'ROTH 1.0';
    rangeDem  = 'J6:J245285';        
    startYr   = 2023;
    yearLen   = 8760;

    % Load demand data
    fprintf('  Loading Demand...\n');
    Demand = xlsread(xlsFile, sheetName, rangeDem);
    Demand = Demand(:);
    T      = numel(Demand);
    nYears = floor(T / yearLen);

    % Load capacity factors (Solar CF)
    fprintf('  Loading Solar CF...\n');
    cf_single = readmatrix(xlsFile, 'Sheet', sheetName, 'Range', 'L6:L8765');
    cf_single(isnan(cf_single)) = 0;
    cf = repmat(cf_single, ceil(T / 8760), 1);
    cf = cf(1:T);

    % Load emission factors
    fprintf('  Loading Emission Factors...\n');
    cSolar_year  = readmatrix(xlsFile, 'Sheet', 'PVEmissions', 'Range', 'C9:C36');
    cBatt_year   = readmatrix(xlsFile, 'Sheet', 'StoargeEmission', 'Range', 'C8:C35');
    
    
    c = [0.012; 0.03695; 0.486; 0.9; 0.04]; % [Nuclear, Solar_base, Gas, Coal, Batt_base]
    
    EF_year = zeros(5, nYears);
    EF_year(1,:) = c(1);                    % Nuclear
    EF_year(2,:) = cSolar_year(1:nYears).'; % Solar (time-varying)
    EF_year(3,:) = c(3);                    % Gas
    EF_year(4,:) = c(4);                    % Coal
    EF_year(5,:) = cBatt_year(1:nYears).';  % Battery (time-varying)
    
    srcNames = ["Nuclear", "Solar", "Gas", "Coal", "Battery"];

    % Define unified color palette for the project
    colorsBase.Nuclear = [0.25 0.35 0.60]; 
    colorsBase.Gas     = [0.75 0.25 0.25];
    colorsBase.Batt    = [0.30 0.65 0.40];
    colorsBase.Solar   = [0.90 0.75 0.25];
    colorsBase.Coal    = [0.55 0.35 0.65]; 
    colorsBase.Waste   = [0.60 0.60 0.60]; 

    % Pack all variables into a single struct to be passed around
    globalData.Demand     = Demand;
    globalData.cf         = cf;
    globalData.EF_year    = EF_year;
    globalData.srcNames   = srcNames;
    globalData.colorsBase = colorsBase;
    globalData.startYr    = startYr;
    globalData.yearLen    = yearLen;
    globalData.T          = T;
    globalData.nYears     = nYears;
    
    fprintf('Initialization complete!\n\n');
end

function [KPI, scenRoot, fullKpiFile] = SELECT_SUMMARY_FILE()
    % Function to select KPI_summary file (supports MAT or CSV)
    [fn, fp] = uigetfile( ...
        {'*.mat;*.csv', 'KPI summary files (*.mat, *.csv)'; ...
         '*.csv',       'CSV files (*.csv)'; ...
         '*.mat',       'MAT files (*.mat)'; ...
         '*.*',         'All files (*.*)'}, ...
        'Select KPI_summary file');

    if isequal(fn, 0)
        error('No KPI_summary file selected. Aborting.');
    end

    fullKpiFile = fullfile(fp, fn);
    [~, ~, ext] = fileparts(fullKpiFile);

    switch lower(ext)
        case '.mat'
            S = load(fullKpiFile);
            if ~isfield(S, 'KPI')
                error('The MAT file does not contain a variable named "KPI".');
            end
            KPI = S.KPI;
            if ~istable(KPI)
                error('"KPI" in the MAT file is not a table.');
            end
        case '.csv'
            KPI = readtable(fullKpiFile);
        otherwise
            error('Unsupported file extension: %s', ext);
    end

    % Clean scenario names if necessary
    if iscell(KPI.Scenario) || ischar(KPI.Scenario)
        KPI.Scenario = string(KPI.Scenario);
    end
    if any(KPI.Scenario == "S101_Special")
        KPI = KPI(KPI.Scenario ~= "S101_Special", :);
    end

    % =========================================================
    % HARD TECHNICAL FILTER (Remove failed or violating scenarios)
    % =========================================================
    initialCount = height(KPI);
    
    % Condition 1: Keep only OPTIMAL scenarios
    if ismember("ResultStatus", string(KPI.Properties.VariableNames))
        KPI = KPI(string(KPI.ResultStatus) == "OPTIMAL", :);
    end
    
    % Condition 2: Remove scenarios violating MaxCost (allowing 0.1% solver tolerance)
    if ismember("TotalCost_AllYears", string(KPI.Properties.VariableNames)) && ...
       ismember("MaxCost", string(KPI.Properties.VariableNames))
        KPI = KPI(KPI.TotalCost_AllYears <= (KPI.MaxCost * 1.001), :);
    end
    
    removedCount = initialCount - height(KPI);
    
    % Locate scenarios folder relative to KPI file
    scenRoot = locateScenariosFolder(fullKpiFile);
    
    fprintf('Loaded KPI table successfully.\n');
    fprintf('  Initial scenarios: %d\n', initialCount);
    fprintf('  Removed by Hard Filter: %d\n', removedCount);
    fprintf('  Remaining scenarios: %d\n\n', height(KPI));
end

function ANALYZE_SUMMARY_UI(KPI, scenRoot, gData)
    % Main UI function displaying all summary results in a single window with tabs and pure white/black styling
    
    re_all = KPI.RenewablesPct2050(:);
    re_all = re_all(isfinite(re_all));
    reTargets = linspace(min(re_all), max(re_all), 11);

    % Create main window with white background
    summaryFig = uifigure('Name', 'Summary Analysis Dashboard - All Scenarios', 'Position', [100 100 1300 750], 'Color', 'white');
    tg = uitabgroup(summaryFig, 'Position', [10 10 1280 730]);

    % --- Tab 1: 3D Mesh (% Renewables) ---
    tab1 = uitab(tg, 'Title', '3D Mesh (%RE)', 'BackgroundColor', 'white');
    ax1 = uiaxes(tab1, 'Position', [50 50 1180 620], 'Color', 'white');
    MESH3D_RESULTS_UI(KPI, ax1, 'RE');

    % --- Tab 2: 3D Mesh (Total Emissions) ---
    tab2 = uitab(tg, 'Title', '3D Mesh (Emissions)', 'BackgroundColor', 'white');
    ax2 = uiaxes(tab2, 'Position', [50 50 1180 620], 'Color', 'white');
    MESH3D_RESULTS_UI(KPI, ax2, 'Emissions');

    % --- Heatmap (% Renewables) ---
    tabH1 = uitab(tg, 'Title', 'Heatmap (%RE)', 'BackgroundColor', 'white');
    axH1  = uiaxes(tabH1, 'Position', [50 50 1180 620], 'Color', 'white');
    HEATMAP_RESULTS_UI(KPI, axH1, 'RE');

    % --- Heatmap (Total Emissions) ---
    tabH2 = uitab(tg, 'Title', 'Heatmap (Emissions)', 'BackgroundColor', 'white');
    axH2  = uiaxes(tabH2, 'Position', [50 50 1180 620], 'Color', 'white');
    HEATMAP_RESULTS_UI(KPI, axH2, 'Emissions');

    % --- Cumulative emissions vs budget ---
    tabCB = uitab(tg, 'Title', 'Cumulative Emissions vs Budget', 'BackgroundColor', 'white');
    axCB  = uiaxes(tabCB, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_CUMEM_VS_BUDGET_UI(KPI, axCB);

    % --- Tab 3: 2050 Demand Cover ---
    tab3 = uitab(tg, 'Title', '2050 Demand Cover', 'BackgroundColor', 'white');
    ax3 = uiaxes(tab3, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_DEMAND_COVER_STACK_2050_UI(KPI, scenRoot, reTargets, gData.colorsBase, ax3);

    % --- Tab 4: 2050 Annual Costs ---
    tab4 = uitab(tg, 'Title', '2050 Annual Costs', 'BackgroundColor', 'white');
    ax4 = uiaxes(tab4, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_COST2050_STACK_UI(KPI, scenRoot, gData.colorsBase, reTargets, gData.EF_year, ax4);

    % --- Tab 5: 2050 Installed Capacity ---
    tab5 = uitab(tg, 'Title', '2050 Installed Capacity', 'BackgroundColor', 'white');
    ax5 = uiaxes(tab5, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_CAPACITY2050_STACK_UI(KPI, gData.colorsBase, reTargets, ax5);

    % --- Tab 6: Emissions (All Years) ---
    tab6 = uitab(tg, 'Title', 'Emissions (All Years)', 'BackgroundColor', 'white');
    ax6 = uiaxes(tab6, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_EMISSIONS_ALLYEARS_UI(KPI, scenRoot, reTargets, gData.colorsBase, gData.EF_year, ax6);
end

function scenRoot = locateScenariosFolder(fullKpiFile)
    kpiDir = fileparts(fullKpiFile);
    runDir = fileparts(kpiDir);
    cand1  = fullfile(runDir, 'scenarios');
    if isfolder(cand1)
        scenRoot = cand1;
        return;
    end
    scenRoot = '';
    d = kpiDir;
    for k = 1:6
        d = fileparts(d);
        cand = fullfile(d, 'scenarios');
        if isfolder(cand)
            scenRoot = cand;
            return;
        end
    end
    error('Could not locate scenarios folder relative to KPI file:\n  %s', fullKpiFile);
end

%% ============================================================
%  UI PLOTTING FUNCTIONS (Pure black text and white background)
% ============================================================

function local_styleAxes(ax)
    % Force white background and black text/ticks/lines for professional publication style
    ax.Color = 'white';
    ax.XColor = 'black';
    ax.YColor = 'black';
    if isprop(ax, 'ZColor')
        ax.ZColor = 'black';
    end
    ax.FontName = 'Helvetica';
    ax.FontSize = 16; 
    grid(ax, 'on');
    box(ax, 'on');
end

function MESH3D_RESULTS_UI(KPI, ax, mode)
    x = KPI.MaxCost(:) / 1e11;
    y = KPI.MaxAreaSolar(:);
    
    if strcmpi(mode, 'Emissions')
        z = KPI.TotalEmissions_AllYears(:) / 1e6; % Convert to MtCO2e
        zLabelStr = 'Total Emissions (All Years) [MtCO_2e]';
        titleStr = 'Mesh: Cost vs Land vs Total Emissions (All Years)';
    else
        z = KPI.RenewablesPct2050(:);
        zLabelStr = '% Renewables (2050)';
        titleStr = 'Mesh: Cost vs Land vs %RE (2050)';
    end

    m = isfinite(x) & isfinite(y) & isfinite(z);
    x = x(m); y = y(m); z = z(m);

        % Regular grid (no triangulation): missing scenarios stay as holes
    xs = unique(x);  ys = unique(y);
    [X, Y] = meshgrid(xs, ys);
    Z = nan(size(X));
    for k = 1:numel(x)
        Z(ys == y(k), xs == x(k)) = z(k);
    end

    local_styleAxes(ax);
    hold(ax, 'on');

    % Main grid (A400-A850): regular mesh
    mainRows = ys >= 400;
    mesh(ax, X(mainRows,:), Y(mainRows,:), Z(mainRows,:), ...
        'FaceColor', 'none', 'EdgeColor', 'interp', 'LineWidth', 1);

    

    xlabel(ax, 'Budget [₪×10^{11}]', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax, 'Solar land cap [km^2]', 'FontWeight', 'bold', 'Color', 'black');
    zlabel(ax, zLabelStr, 'FontWeight', 'bold', 'Color', 'black');
    title(ax, strrep(titleStr, 'Cost', 'Budget'), 'Color', 'black', 'FontWeight', 'bold');
    view(ax, [-35, 20]);
    axis(ax, 'tight');
    
    cb = colorbar(ax);
    cb.Color = 'black';
end

function HEATMAP_RESULTS_UI(KPI, ax, mode)
% 2D heatmap: budget (x) x solar land cap (y), value written in each cell.
% Missing (infeasible) scenarios are shown as "infeasible".
    x = KPI.MaxCost(:) / 1e11;
    y = KPI.MaxAreaSolar(:);

    if strcmpi(mode, 'Emissions')
        z = KPI.TotalEmissions_AllYears(:) / 1e6;
        fmt = '%.0f';
        cbLabel  = 'Total emissions 2023-2050 [MtCO_2e]';
        titleStr = 'Total emissions 2023-2050 [MtCO_2e] by budget and land cap';
        cmap = flipud(parula(256));      % low emissions = bright
    else
        z = KPI.RenewablesPct2050(:);
        fmt = '%.1f';
        cbLabel  = '% Renewables (2050)';
        titleStr = '% Renewables in 2050 by budget and land cap';
        cmap = parula(256);              % high RE = bright
    end

    m = isfinite(x) & isfinite(y) & isfinite(z);
    x = round(x(m), 2);  y = y(m);  z = z(m);
    xs = unique(x);  ys = unique(y);
    Z = nan(numel(ys), numel(xs));
    for k = 1:numel(x)
        Z(ys == y(k), xs == x(k)) = z(k);
    end

    local_styleAxes(ax);
    hold(ax, 'on');
    imagesc(ax, 1:numel(xs), 1:numel(ys), Z, 'AlphaData', ~isnan(Z));
    set(ax, 'YDir', 'normal');
    colormap(ax, cmap);

    % colour scale from the main grid (>=400 km2) so the 100 km2 row does not compress it
    mainVals = Z(ys >= 400, :);
    caxis(ax, [min(mainVals(:)) max(mainVals(:))]);
    lim = caxis(ax);

    for i = 1:numel(ys)
        for j = 1:numel(xs)
            v = Z(i, j);
            if isnan(v)
                txt = 'infeasible';  col = [0.5 0.5 0.5];
            else
                txt = sprintf(fmt, v);
                t = (min(max(v, lim(1)), lim(2)) - lim(1)) / diff(lim);
                if strcmpi(mode, 'Emissions'), dark = t > 0.5; else, dark = t < 0.5; end
                col = [1 1 1] * dark;    % white text on dark cells, black on bright
            end
            text(ax, j, i, txt, 'HorizontalAlignment', 'center', ...
                'FontSize', 10, 'FontWeight', 'bold', 'Color', col);
        end
    end

    xticks(ax, 1:numel(xs));  xticklabels(ax, compose('%d', round(xs * 100)));   % 4.05 -> 405 [x10^9]
    yticks(ax, 1:numel(ys));  yticklabels(ax, compose('%d', ys));
    xlim(ax, [0.5 numel(xs)+0.5]);  ylim(ax, [0.5 numel(ys)+0.5]);
    grid(ax, 'off');  ax.Box = 'on';  view(ax, 2);

    xlabel(ax, 'Budget [₪×10^{9}]', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax, 'Solar land cap [km^2]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, titleStr, 'Color', 'black', 'FontWeight', 'bold');

    cb = colorbar(ax);
    cb.Color = 'black';
    cb.Label.String = cbLabel;
end

function PLOT_CUMEM_VS_BUDGET_UI(KPI, ax)
% Cumulative emissions 2023-2050 vs budget, one line per solar land cap.
    x = round(KPI.MaxCost(:) / 1e11, 2);
    y = KPI.MaxAreaSolar(:);
    z = KPI.TotalEmissions_AllYears(:) / 1e6;
    areas = unique(y);
    cmap  = parula(numel(areas) + 1);

    local_styleAxes(ax);
    hold(ax, 'on');
    h = gobjects(numel(areas), 1);
    for k = 1:numel(areas)
        m = y == areas(k);
        [xs, o] = sort(x(m));  zs = z(m);  zs = zs(o);
        h(k) = plot(ax, xs, zs, '-o', 'Color', cmap(k,:), 'MarkerFaceColor', cmap(k,:), ...
            'LineWidth', 1.8, 'MarkerSize', 6);
    end
    grid(ax, 'on');
    xticks(ax, unique(x));
    xlabel(ax, 'Budget [₪×10^{11}]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 16);
    ylabel(ax, 'Cumulative emissions 2023–2050 [MtCO_2e]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 16);
    title(ax, 'Cumulative emissions vs budget, by solar land cap', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 18);
    lg = legend(ax, h, compose('%d km^2', areas), 'Location', 'eastoutside');
    lg.Title.String = 'Land cap';  lg.Color = 'white';  lg.TextColor = 'black';  lg.FontSize = 13;
end

function PLOT_DEMAND_COVER_STACK_2050_UI(KPI, scenRoot, ~, colorsBase, ax)
    K = KPI(isfinite(KPI.RenewablesPct2050), :);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    Y_MWh = zeros(0, 5);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        if ~isfield(RES,'genYear') || ~isfield(RES,'BaseYear'), continue; end

        y2050 = 2050 - RES.BaseYear + 1;
        if y2050 < 1 || y2050 > size(RES.genYear,2), continue; end

        nRows = size(RES.genYear,1);
        solar = 0; gas = 0; coal = 0; batt = 0;
        if nRows >= 2 && isfinite(RES.genYear(2, y2050)), solar = RES.genYear(2, y2050); end
        if nRows >= 3 && isfinite(RES.genYear(3, y2050)), gas   = RES.genYear(3, y2050); end
        if nRows >= 4 && isfinite(RES.genYear(4, y2050)), coal  = RES.genYear(4, y2050); end
        if nRows >= 5 && isfinite(RES.genYear(5, y2050)), batt  = RES.genYear(5, y2050); end

        dump = 0;
        if isfield(RES,'Dump2050_MWh') && isfinite(RES.Dump2050_MWh), dump = RES.Dump2050_MWh; end

        Y_MWh(end+1,:) = [gas, batt, solar, coal, dump];
    end

    Y = Y_MWh / 1e6; % TWh
    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:size(Y,1), Y, 'stacked', 'EdgeColor', 'none');

    hb(1).FaceColor = colorsBase.Gas;
    hb(2).FaceColor = colorsBase.Batt;
    hb(3).FaceColor = colorsBase.Solar;
    hb(4).FaceColor = colorsBase.Coal;
    hb(5).FaceColor = colorsBase.Waste;

    ylabel(ax, 'Energy in 2050 [TWh]', 'FontWeight', 'bold', 'Color', 'black');
    xlabel(ax, 'Renewables Share in 2050 [%]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, '2050 Demand coverage by source (All scenarios)', 'Color', 'black', 'FontWeight', 'bold');
    
    lg = legend(ax, {'Gas', 'Battery (Charge from solar)', 'Solar to grid', 'Coal', 'Waste Solar'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';

    local_applyXReTicks(ax, re_sorted);
end

function PLOT_COST2050_STACK_UI(KPI, scenRoot, colorsBase, ~, EF_year, ax)
    K = KPI(isfinite(KPI.RenewablesPct2050), :);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    keptCost = zeros(0, 9);
    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        if ~isfield(RES,'BaseYear') || ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource'), continue; end

        y2050Idx = 2050 - RES.BaseYear + 1;
        nYears = size(RES.opCostYearBySource,2);
        if y2050Idx < 1 || y2050Idx > nYears, continue; end

        C50 = local_costYear(RES, y2050Idx);
        opex_gas   = C50.opex(3);  capex_gas   = C50.capex(3);
        opex_batt  = C50.opex(5);  capex_batt  = C50.capex(5);
        opex_solar = C50.opex(2);  capex_solar = C50.capex(2);
        opex_coal  = C50.opex(4);  capex_coal  = C50.capex(4);


        capSolar2050 = K.Cap2050_Solar(s); if ~isfinite(capSolar2050), capSolar2050 = 0; end
        capBatt2050  = K.Cap2050_Battery(s); if ~isfinite(capBatt2050), capBatt2050 = 0; end
        ext2050_NIS  = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050, capBatt2050);

        rowBillion = [opex_gas, capex_gas, opex_batt, capex_batt, opex_solar, capex_solar, opex_coal, capex_coal, ext2050_NIS] / 1e9;
        keptCost(end+1, :) = rowBillion;
    end

    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:size(keptCost,1), keptCost, 'stacked', 'EdgeColor', 'none');
    
    palette = [
        colorsBase.Gas; 0.65*colorsBase.Gas + 0.35*[1 1 1];
        colorsBase.Batt; 0.65*colorsBase.Batt + 0.35*[1 1 1];
        colorsBase.Solar; 0.65*colorsBase.Solar + 0.35*[1 1 1];
        colorsBase.Coal; 0.65*colorsBase.Coal + 0.35*[1 1 1];
        [0.35 0.35 0.35]
    ];
    for k = 1:numel(hb), hb(k).FaceColor = palette(k,:); end

    ylabel(ax, 'Annual cost in 2050 [billion ₪]', 'FontWeight', 'bold', 'Color', 'black');
    xlabel(ax, 'Renewables Share in 2050 [%]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, 'Annual system cost in 2050 - OPEX + CAPEX + externalities', 'Color', 'black', 'FontWeight', 'bold');
    
    lg = legend(ax, {'Gas (OPEX)', 'Gas (CAPEX)', 'Battery (OPEX)', 'Battery (CAPEX)', 'Solar (OPEX)', 'Solar (CAPEX)', 'Coal (OPEX)', 'Coal (CAPEX)', 'Externalities'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';

    local_applyXReTicks(ax, re_sorted);
end

function PLOT_CAPACITY2050_STACK_UI(KPI, colorsBase, ~, ax)
    K = KPI(isfinite(KPI.RenewablesPct2050), :);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    Y_stack = [K.Cap2050_Gas, K.Cap2050_Solar, K.Cap2050_Coal] / 1000; % GW
    Y_batt  = K.Cap2050_Battery(:) / 1000;

    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:height(K), Y_stack, 'stacked', 'EdgeColor', 'none', 'BarWidth', 0.75);
    hb(1).FaceColor = colorsBase.Gas;
    hb(2).FaceColor = colorsBase.Solar;
    hb(3).FaceColor = colorsBase.Coal;

    bar(ax, (1:height(K)) + 0.32, Y_batt, 'FaceColor', colorsBase.Batt, 'EdgeColor', 'none', 'BarWidth', 0.28);

    ylabel(ax, 'Installed capacity in 2050 [GW]', 'FontWeight', 'bold', 'Color', 'black');
    xlabel(ax, 'Renewables Share in 2050 [%]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, 'Installed capacity in 2050 by source', 'Color', 'black', 'FontWeight', 'bold');
    
    lg = legend(ax, {'Gas', 'Solar', 'Coal', 'Battery'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';

    local_applyXReTicks(ax, re_sorted);
end

function PLOT_EMISSIONS_ALLYEARS_UI(KPI, scenRoot, ~, colorsBase, EF_year, ax)
    K = KPI(isfinite(KPI.RenewablesPct2050), :);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    Y_stack_tCO2e = zeros(0, 5);
    srcNames = ["Nuclear", "Solar", "Gas", "Coal", "Battery"];

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        if ~isfield(RES,'genYear'), continue; end

        G = local_genForEmissions(RES);;
        nYuse = min(size(EF_year,2), size(G,2));
        emisBySrc = sum(G(:, 1:nYuse) .* EF_year(:, 1:nYuse), 2).';
        Y_stack_tCO2e(end+1,:) = emisBySrc;
    end

    Y_stack_Mt = Y_stack_tCO2e / 1e6;
    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:size(Y_stack_Mt,1), Y_stack_Mt, 'stacked', 'EdgeColor', 'none');
    
    local_applyColors(hb, srcNames, colorsBase);

    ylabel(ax, 'Total emissions (all years) [MtCO2e]', 'FontWeight', 'bold', 'Color', 'black');
    xlabel(ax, 'Renewables Share in 2050 [%]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, 'Total emissions by source (all years, stacked)', 'Color', 'black', 'FontWeight', 'bold');
    
    lg = legend(ax, cellstr(srcNames), 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';

    local_applyXReTicks(ax, re_sorted);
end

function local_applyColors(hb, srcNames, colorsBase)
    n = numel(hb);
    C = lines(n);
    for i = 1:n
        nm = lower(string(srcNames(i)));
        if contains(nm,"gas") && isfield(colorsBase,'Gas'), hb(i).FaceColor = colorsBase.Gas; continue; end
        if contains(nm,"coal") && isfield(colorsBase,'Coal'), hb(i).FaceColor = colorsBase.Coal; continue; end
        if contains(nm,"solar") && isfield(colorsBase,'Solar'), hb(i).FaceColor = colorsBase.Solar; continue; end
        if contains(nm,"batt") && isfield(colorsBase,'Batt'), hb(i).FaceColor = colorsBase.Batt; continue; end
        if contains(nm,"nuclear") && isfield(colorsBase,'Nuclear'), hb(i).FaceColor = colorsBase.Nuclear; continue; end
        hb(i).FaceColor = C(i,:);
    end
end

function local_applyXReTicks(ax, re_sorted)
    % Helper function to set X-axis ticks displaying actual renewable percentage values in black text
    n = numel(re_sorted);
    if n == 0, return; end

    if n <= 15
        idxTicks = 1:n;
    else
        idxTicks = unique([1, round(linspace(1, n, 12)), n]);
    end

    xticks(ax, idxTicks);
    xticklabels(ax, arrayfun(@(v) sprintf('%.1f%%', v), re_sorted(idxTicks), 'UniformOutput', false));
    xtickangle(ax, 45);
    
    % Ensure tick labels color is black
    ax.XAxis.Color = 'black';
    ax.YAxis.Color = 'black';
end

function ext2050_NIS = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW)
% Externalities of year y in UNDISCOUNTED NIS.
%   'model' : identical to what the optimization charged inside the budget
%             (RES.extCostYearBySource, 200 NIS/t on nuclear/gas/coal)
%   'scc'   : sensitivity - SCC 125 USD/t on all life-cycle emissions + EOL costs
    EXT_MODE = 'model';

    switch EXT_MODE
        case 'model'
            df = RES.P.df_yearly(y2050Idx);
            ext2050_NIS = sum(RES.extCostYearBySource(:, y2050Idx)) / df;

        case 'scc'
            FX = 3.7;
            SCC = 125 * FX;
            EOL_SOLAR = (10000/30) * FX;
            EOL_BATT  = (50000/20) * FX;
            G  = local_genForEmissions(RES);
            G  = G(:, y2050Idx);
            EF = EF_year(:, y2050Idx);
            G(~isfinite(G)) = 0; EF(~isfinite(EF)) = 0;
            extClimate = sum(G .* EF) * SCC;
            extEOL = (capSolar2050_MW * EOL_SOLAR) + (capBatt2050_MW * EOL_BATT);
            ext2050_NIS = extClimate + extEOL;
    end
end



function selectedScenarioName = SELECT_SPECIFIC_SCENARIO(KPI)
    % Open a UI list dialog to select one scenario from the KPI table
    scenarioList = string(KPI.Scenario);
    
    [indx, tf] = listdlg('PromptString', 'Select a scenario to analyze:', ...
                         'SelectionMode', 'single', ...
                         'ListSize', [300 400], ...
                         'ListString', cellstr(scenarioList));
                     
    if tf == 1
        selectedScenarioName = scenarioList(indx);
        fprintf('Selected Scenario: %s\n\n', selectedScenarioName);
    else
        selectedScenarioName = "";
        warning('No scenario selected.');
    end
end

function ANALYZE_SPECIFIC_SCENARIO_UI(scName, scenRoot, gData, KPI)
    % Main UI function displaying specific scenario results in a single window with tabs and white/black styling
    
    resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
    if ~isfile(resFile)
        error('Missing results_heavy.mat for scenario: %s', scName);
    end
    
    fprintf('Loading results for %s...\n', scName);
    S = load(resFile, 'RES');
    if ~isfield(S,'RES') || ~isstruct(S.RES)
        error('Invalid RES struct in %s', resFile);
    end
    RES = S.RES;
    
    % Get capacity for battery 2050 plot
    capBatt2050_MW = 0;
    idxKPI = find(string(KPI.Scenario) == scName, 1);
    if ~isempty(idxKPI) && ismember("Cap2050_Battery", string(KPI.Properties.VariableNames))
        capBatt2050_MW = KPI.Cap2050_Battery(idxKPI);
    end

    % Create main window with white background
    scenFig = uifigure('Name', sprintf('Scenario Analysis Dashboard - %s', scName), 'Position', [150 150 1300 750], 'Color', 'white');
    tg = uitabgroup(scenFig, 'Position', [10 10 1280 730]);

    % --- Tab 1: Interactive Generation Mix (Drill-down) ---
    tab1 = uitab(tg, 'Title', 'Interactive Generation Mix', 'BackgroundColor', 'white');
    ax1 = uiaxes(tab1, 'Position', [50 50 1180 620], 'Color', 'white');
    
    % Back Button for drill-down (initially hidden)
    backBtn = uibutton(tab1, 'push', 'Text', '<< Back', 'Position', [50 680 100 30], 'Visible', 'off', 'BackgroundColor', 'white', 'FontColor', 'black');
    
    PLOT_INTERACTIVE_MIX_UI(RES, gData, ax1, backBtn);

    % --- Tab 2: Capacity Growth (Stairs) ---
    tab2 = uitab(tg, 'Title', 'Capacity Growth (Stairs)', 'BackgroundColor', 'white');
    ax2 = uiaxes(tab2, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_CAPACITY_GROWTH_UI(RES, gData.colorsBase, ax2, 'stairs');

    % --- Tab 3: Capacity Growth (Stacked) ---
    tab3 = uitab(tg, 'Title', 'Capacity Growth (Stacked)', 'BackgroundColor', 'white');
    ax3 = uiaxes(tab3, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_CAPACITY_GROWTH_UI(RES, gData.colorsBase, ax3, 'stacked');

    % --- Tab 4: Battery Energy 2050 ---
    tab4 = uitab(tg, 'Title', 'Battery Energy (2050)', 'BackgroundColor', 'white');
    ax4 = uiaxes(tab4, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_BATTERY_2050_UI(RES, gData.colorsBase, capBatt2050_MW, ax4);

% --- Tab 5: Custom Hourly Mix (Date Range) ---
    tab5 = uitab(tg, 'Title', 'Custom Hourly Mix', 'BackgroundColor', 'white');
    ax5 = uiaxes(tab5, 'Position', [50 50 1180 620], 'Color', 'white');

    % UI Controls for Date Selection
    uilabel(tab5, 'Text', 'Start Date:', 'Position', [50 690 70 22], 'FontColor', 'black', 'FontWeight', 'bold');
    dpStart = uidatepicker(tab5, 'Position', [120 690 120 22], 'Value', datetime(2050, 6, 17));

    uilabel(tab5, 'Text', 'End Date:', 'Position', [260 690 70 22], 'FontColor', 'black', 'FontWeight', 'bold');
    dpEnd = uidatepicker(tab5, 'Position', [330 690 120 22], 'Value', datetime(2050, 6, 25));

    btnUpdate = uibutton(tab5, 'push', 'Text', 'Update Plot', ...
        'Position', [470 690 100 22], ...
        'BackgroundColor', 'white', 'FontColor', 'black', ...
        'ButtonPushedFcn', @(~,~) PLOT_CUSTOM_RANGE_UI(RES, gData, ax5, dpStart.Value, dpEnd.Value, scName));

    % Render initial plot for default dates
    PLOT_CUSTOM_RANGE_UI(RES, gData, ax5, dpStart.Value, dpEnd.Value, scName);

    % --- Tab 6: Battery Energy Level (Date Range) ---
    tab6 = uitab(tg, 'Title', 'Battery Level', 'BackgroundColor', 'white');
    ax6 = uiaxes(tab6, 'Position', [50 50 1180 620], 'Color', 'white');


    % UI Controls for Date Selection (Default to January for Winter profile)
    uilabel(tab6, 'Text', 'Start Date:', 'Position', [50 690 70 22], 'FontColor', 'black', 'FontWeight', 'bold');
    dpStart6 = uidatepicker(tab6, 'Position', [120 690 120 22], 'Value', datetime(2050, 1, 1));

    uilabel(tab6, 'Text', 'End Date:', 'Position', [260 690 70 22], 'FontColor', 'black', 'FontWeight', 'bold');
    dpEnd6 = uidatepicker(tab6, 'Position', [330 690 120 22], 'Value', datetime(2050, 1, 31));

    btnUpdate6 = uibutton(tab6, 'push', 'Text', 'Update Plot', ...
        'Position', [470 690 100 22], ...
        'BackgroundColor', 'white', 'FontColor', 'black', ...
        'ButtonPushedFcn', @(~,~) PLOT_CUSTOM_BATTERY_RANGE_UI(RES, gData, ax6, dpStart6.Value, dpEnd6.Value, scName));

    % Render initial plot for default dates
    PLOT_CUSTOM_BATTERY_RANGE_UI(RES, gData, ax6, dpStart6.Value, dpEnd6.Value, scName);

  % --- Tab 7: LCOE Over Time ---
    tab7 = uitab(tg, 'Title', 'LCOE Over Time', 'BackgroundColor', 'white');
    ax7 = uiaxes(tab7, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_LCOE_OVER_TIME_UI(RES, gData, ax7);
end

%% ============================================================
%  SPECIFIC SCENARIO PLOTTING FUNCTIONS
% ============================================================

function PLOT_INTERACTIVE_MIX_UI(RES, gData, ax, backBtn)
    % Prepares data and state for the interactive drill-down generation mix
    
    if ~isfield(RES,'U') || isempty(RES.U)
        title(ax, 'No hourly generation data (RES.U) available.');
        return;
    end
    
    U = RES.U;
    nSrc = size(U,1);
    T = size(U,2);
    
    ChB  = zeros(1, T);
    Dump = zeros(1, T);
    if isfield(RES,'ChB') && ~isempty(RES.ChB), ChB = RES.ChB(:).'; end
    if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:).'; end
    
    % Pad sources if needed (assuming order: Nuclear, Solar, Gas, Coal, Battery)
    U_nuc = zeros(1,T); U_sol = zeros(1,T); U_gas = zeros(1,T); U_coal = zeros(1,T); U_batt = zeros(1,T);
    if nSrc >= 1, U_nuc  = U(1,:); end
    if nSrc >= 2, U_sol  = U(2,:); end
    if nSrc >= 3, U_gas  = U(3,:); end
    if nSrc >= 4, U_coal = U(4,:); end
    if nSrc >= 5, U_batt = U(5,:); end
    
    Y_all = [U_nuc; U_gas; U_coal; U_sol; U_batt; ChB; Dump]'; % [T x 7]
    
    c = gData.colorsBase;
    cmap = [c.Nuclear; c.Gas; c.Coal; c.Solar; c.Batt; [0.40 0.80 0.85]; c.Waste];
    legNames = {'Nuclear', 'Gas', 'Coal', 'Solar to grid', 'Battery from Solar', 'Solar to Battery', 'Solar Wasted'};
    
    % Initialize state for drill-down logic in axes UserData
    state.currentLevel = 0; % 0: Annual, 1: Daily, 2: Hourly
    state.selectedYear = gData.startYr;
    state.selectedDay  = 1;
    state.Y_all        = Y_all;
    state.startYr      = gData.startYr;
    state.nYears       = floor(T / 8760);
    state.cmap         = cmap;
    state.legNames     = legNames;
    
    ax.UserData = state;
    backBtn.ButtonPushedFcn = @(src, event) GO_BACK_LEVEL(ax, backBtn);
    
    % Render initial view (Annual)
    RENDER_MIX_LEVEL(ax, backBtn);
end

function RENDER_MIX_LEVEL(ax, backBtn)
    % Renders the generation mix based on the current drill-down level
    state = ax.UserData;
    cla(ax);
    local_styleAxes(ax);
    hold(ax, 'on');
    
    Y_all = state.Y_all;
    
    if state.currentLevel == 0
        % --- LEVEL 0: ANNUAL ---
        backBtn.Visible = 'off';
        
        Y_ann = zeros(state.nYears, 7);
        for y = 1:state.nYears
            idxStart = (y-1)*8760 + 1;
            idxEnd   = y*8760;
            if idxEnd <= size(Y_all, 1)
                Y_ann(y, :) = sum(Y_all(idxStart:idxEnd, :), 1) / 1e6; % Convert MWh to TWh
            end
        end
        
        x_vals = state.startYr : (state.startYr + state.nYears - 1);
        hb = bar(ax, x_vals, Y_ann, 'stacked', 'EdgeColor', 'none', 'HitTest', 'on');
        
        ylabel(ax, 'Energy [TWh]', 'FontWeight', 'bold', 'Color', 'black');
        xlabel(ax, 'Year', 'FontWeight', 'bold', 'Color', 'black');
        title(ax, 'Annual Generation Mix (Click a bar to see daily mix)', 'Color', 'black', 'FontWeight', 'bold');
        
        % Make bars clickable
        for k = 1:numel(hb)
            hb(k).FaceColor = state.cmap(k,:);
            hb(k).ButtonDownFcn = @(src, event) BAR_CLICKED(ax, backBtn, event);
        end
        
    elseif state.currentLevel == 1
        % --- LEVEL 1: DAILY ---
        backBtn.Visible = 'on';
        
        yIdx = state.selectedYear - state.startYr + 1;
        idxStart = (yIdx-1)*8760 + 1;
        idxEnd   = yIdx*8760;
        Y_year = Y_all(idxStart:idxEnd, :);
        
        Y_day = zeros(365, 7);
        for d = 1:365
            dStart = (d-1)*24 + 1;
            dEnd   = d*24;
            Y_day(d, :) = sum(Y_year(dStart:dEnd, :), 1) / 1000; % Convert MWh to GWh
        end
        
        x_vals = 1:365;
        hb = bar(ax, x_vals, Y_day, 'stacked', 'EdgeColor', 'none', 'HitTest', 'on', 'BarWidth', 1);
        
        ylabel(ax, 'Energy [GWh]', 'FontWeight', 'bold', 'Color', 'black');
        xlabel(ax, 'Day of the Year', 'FontWeight', 'bold', 'Color', 'black');
        title(ax, sprintf('Daily Generation Mix for %d (Click a day to see hourly mix)', state.selectedYear), 'Color', 'black', 'FontWeight', 'bold');
        
        for k = 1:numel(hb)
            hb(k).FaceColor = state.cmap(k,:);
            hb(k).ButtonDownFcn = @(src, event) BAR_CLICKED(ax, backBtn, event);
        end
        
    elseif state.currentLevel == 2
        % --- LEVEL 2: HOURLY ---
        backBtn.Visible = 'on';
        
        yIdx = state.selectedYear - state.startYr + 1;
        dIdx = state.selectedDay;
        
        % Calculate absolute index for the specific day
        hStart = (yIdx-1)*8760 + (dIdx-1)*24 + 1;
        hEnd   = hStart + 23;
        
        Y_hour = Y_all(hStart:hEnd, :); % MWh
        
        x_vals = 1:24;
        hb = bar(ax, x_vals, Y_hour, 'stacked', 'EdgeColor', 'none', 'BarWidth', 1);
        
        ylabel(ax, 'Energy [MWh]', 'FontWeight', 'bold', 'Color', 'black');
        xlabel(ax, 'Hour of the Day', 'FontWeight', 'bold', 'Color', 'black');
        title(ax, sprintf('Hourly Generation Mix on Day %d, %d', state.selectedDay, state.selectedYear), 'Color', 'black', 'FontWeight', 'bold');
        
        for k = 1:numel(hb)
            hb(k).FaceColor = state.cmap(k,:);
        end
    end
    
    lg = legend(ax, state.legNames, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';
end

function BAR_CLICKED(ax, backBtn, event)
    % Callback triggered when a bar is clicked
    state = ax.UserData;
    
    % Get the X coordinate of the click to determine which bar was clicked
    xClick = round(event.IntersectionPoint(1));
    
    if state.currentLevel == 0
        % Clicked on a year
        if xClick >= state.startYr && xClick < (state.startYr + state.nYears)
            state.selectedYear = xClick;
            state.currentLevel = 1; % Drill down to daily
        end
    elseif state.currentLevel == 1
        % Clicked on a day
        if xClick >= 1 && xClick <= 365
            state.selectedDay = xClick;
            state.currentLevel = 2; % Drill down to hourly
        end
    end
    
    ax.UserData = state;
    RENDER_MIX_LEVEL(ax, backBtn);
end

function GO_BACK_LEVEL(ax, backBtn)
    % Callback for the Back button
    state = ax.UserData;
    if state.currentLevel > 0
        state.currentLevel = state.currentLevel - 1;
        ax.UserData = state;
        RENDER_MIX_LEVEL(ax, backBtn);
    end
end

function PLOT_CAPACITY_GROWTH_UI(RES, colorsBase, ax, type)
    % Plots installed capacity growth over time (Stairs or Stacked)
    
    K = [];
    if isfield(RES,'K') && ~isempty(RES.K), K = RES.K;
    elseif isfield(RES,'Kcap') && ~isempty(RES.Kcap), K = RES.Kcap;
    elseif isfield(RES,'Cap') && ~isempty(RES.Cap), K = RES.Cap;
    else
        title(ax, 'No installed capacity data found.'); return;
    end

    if size(K,1) == size(RES.U,2) && size(K,2) == size(RES.U,1), K = K.'; end
    T = size(K,2);
    
    baseYear = 2023;
    if isfield(RES,'BaseYear') && isfinite(RES.BaseYear), baseYear = RES.BaseYear; end
    dtAll = local_modelDates(baseYear, T, 8760);

    srcNames = {'Nuclear','Solar','Gas','Coal','Battery'};
    srcColors = [colorsBase.Nuclear; colorsBase.Solar; colorsBase.Gas; colorsBase.Coal; colorsBase.Batt];

    Kplot = zeros(T, 5);
    for i = 1:min(size(K,1), 5), Kplot(:,i) = K(i,:).'; end

    % Extract breakpoints
    dK = diff(Kplot, 1, 1);
    changeMask = any(abs(dK) > 0, 2);
    changeIdx  = find(changeMask) + 1;
    bp = unique([1; changeIdx; T]);

    dtBP = dtAll(bp);
    KBP  = Kplot(bp,:);

    local_styleAxes(ax);
    hold(ax, 'on');

    if strcmpi(type, 'stairs')
        for i = 1:5
            stairs(ax, dtBP, KBP(:,i), 'LineWidth', 1.6, 'Color', srcColors(i,:));
        end
        ylabel(ax, 'Installed capacity [MW]', 'FontWeight', 'bold', 'Color', 'black');
        title(ax, 'Installed Capacity Steps Across Horizon', 'Color', 'black', 'FontWeight', 'bold');
    else
        % Stacked Area needs step expansion
        [dtStep, KStep] = local_step_expand(dtBP, KBP);
        hA = area(ax, dtStep, KStep, 'LineStyle', 'none');
        for i = 1:numel(hA)
            hA(i).FaceColor = srcColors(i,:);
            hA(i).FaceAlpha = 1.0;
        end
        ylabel(ax, 'Installed capacity [MW]', 'FontWeight', 'bold', 'Color', 'black');
        title(ax, 'Installed Capacity (Stacked Area) Across Horizon', 'Color', 'black', 'FontWeight', 'bold');
    end

    xlabel(ax, 'Date', 'FontWeight', 'bold', 'Color', 'black');
    lg = legend(ax, srcNames, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white'; lg.TextColor = 'black';
    ax.YAxis.Exponent = 0; ytickformat(ax,'%.0f');
end

function [xStep, YStep] = local_step_expand(x, Y)
    % Helper to create sharp steps for area plots
    n = size(Y,1); m = size(Y,2);
    if n < 2, xStep = x; YStep = Y; return; end
    
    xStep = repmat(x(1), 2*n-1, 1);
    YStep = zeros(2*n-1, m);
    
    row = 1;
    for i = 1:(n-1)
        xStep(row)   = x(i);
        YStep(row,:) = Y(i,:);
        row = row + 1;
        xStep(row)   = x(i+1);
        YStep(row,:) = Y(i,:); 
        row = row + 1;
    end
    xStep(end)   = x(end);
    YStep(end,:) = Y(end,:);
end

function PLOT_BATTERY_2050_UI(RES, colorsBase, capBatt2050_MW, ax)
    % Plots battery energy timeseries specifically for 2050
    
    if ~isfield(RES,'E') && ~isfield(RES,'Ebatt')
        title(ax, 'No battery energy state data found.'); return;
    end
    
    E_all = [];
    if isfield(RES,'E'), E_all = RES.E(:);
    elseif isfield(RES,'Ebatt'), E_all = RES.Ebatt(:); end

    baseYear = 2023;
    if isfield(RES,'BaseYear') && isfinite(RES.BaseYear), baseYear = RES.BaseYear; end
    
    y2050Offset = 2050 - baseYear;
    tStartAbs = y2050Offset * 8760 + 1;
    tEndAbs   = tStartAbs + 8759;

    if tStartAbs < 1 || tEndAbs > numel(E_all)
        title(ax, '2050 range out of bounds for battery series.'); return;
    end

    E2050_MWh = E_all(tStartAbs:tEndAbs);
    E2050_GWh = E2050_MWh / 1000;
    
    dt0 = datetime(2050, 1, 1, 0, 0, 0);
    dt  = dt0 + hours((0:8759)');

    local_styleAxes(ax);
    hold(ax, 'on');
    plot(ax, dt, E2050_GWh, '-', 'LineWidth', 1.0, 'Color', colorsBase.Batt);

    xlabel(ax, 'Date (2050)', 'FontWeight', 'bold', 'Color', 'black');
    ylabel(ax, 'Battery energy [GWh]', 'FontWeight', 'bold', 'Color', 'black');
    title(ax, 'Battery Energy Timeseries in 2050', 'Color', 'black', 'FontWeight', 'bold');

    capBatt_GWh = (capBatt2050_MW * 4) / 1000;
    legTxt = sprintf('Battery energy (Capacity: %.2f GWh)', capBatt_GWh);
    lg = legend(ax, {legTxt}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white'; lg.TextColor = 'black';
    ax.YAxis.Exponent = 0; ytickformat(ax, '%.1f');
end

function PLOT_CUSTOM_RANGE_UI(RES, gData, ax, startDt, endDt, scName)
    % Plots the hourly generation mix for a specific user-defined date range

    % Validate dates
    if startDt > endDt
        cla(ax);
        title(ax, 'Error: Start Date must be before or equal to End Date', 'Color', 'red');
        return;
    end

    % Create full time vector based on the simulation start year
    dtAll = local_modelDates(gData.startYr, gData.T, gData.yearLen);

    % End date should include the full day (up to 23:59)
    endDtFull = endDt + hours(23);
    mask = (dtAll >= startDt) & (dtAll <= endDtFull);

    if ~any(mask)
        cla(ax);
        title(ax, 'No data available for the selected date range.', 'Color', 'red');
        return;
    end

    % Extract generation arrays securely
    U = RES.U;
    ChB = zeros(1, gData.T); if isfield(RES,'ChB'), ChB = RES.ChB(:).'; end
    Dump = zeros(1, gData.T); if isfield(RES,'Dump'), Dump = RES.Dump(:).'; end

    nSrc = size(U,1);
    U_nuc = zeros(1,gData.T); U_sol = zeros(1,gData.T); U_gas = zeros(1,gData.T); U_coal = zeros(1,gData.T); U_batt = zeros(1,gData.T);
    
    if nSrc >= 1, U_nuc  = U(1,:); end
    if nSrc >= 2, U_sol  = U(2,:); end
    if nSrc >= 3, U_gas  = U(3,:); end
    if nSrc >= 4, U_coal = U(4,:); end
    if nSrc >= 5, U_batt = U(5,:); end

    % Apply date mask
    U_nuc_m  = U_nuc(mask);
    U_gas_m  = U_gas(mask);
    U_coal_m = U_coal(mask);
    U_sol_m  = U_sol(mask);
    U_batt_m = U_batt(mask);
    ChB_m    = ChB(mask);
    Dump_m   = Dump(mask);
    Dem_m    = gData.Demand(mask);
    dt_m     = dtAll(mask);

    % Stacked order: Nuclear, Gas, Coal, Solar to grid, Battery from Solar, Solar to Battery, Solar Wasted
    Y_stacked = [U_nuc_m; U_gas_m; U_coal_m; U_sol_m; U_batt_m; ChB_m; Dump_m]'; % [N x 7]

    % Plotting
    cla(ax);
    local_styleAxes(ax);
    hold(ax, 'on');

    hb = bar(ax, dt_m, Y_stacked, 'stacked', 'EdgeColor', 'none', 'BarWidth', 1);

    % Apply colors exactly matching the provided image style
    c = gData.colorsBase;
    cmap = [c.Nuclear; c.Gas; c.Coal; c.Solar; c.Batt; [0.40 0.80 0.85]; c.Waste];
    
    for k = 1:numel(hb)
        hb(k).FaceColor = cmap(k,:);
    end

    % Plot Demand Line
    plot(ax, dt_m, Dem_m, 'k-', 'LineWidth', 1.2);

% Formatting with increased font sizes
    ylabel(ax, 'Energy [MWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Date', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    
    % Construct Title (You can add the dynamic RE% calculation here later if needed)
    titleStr = sprintf('Hourly Generation Mix (%s) | %s to %s', scName, datestr(startDt, 'dd/mm/yyyy'), datestr(endDt, 'dd/mm/yyyy'));
    title(ax, titleStr, 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);

    % Legend setup with increased font size
    legNames = {'Nuclear', 'Gas', 'Coal', 'Solar to grid', 'Battery from Solar', 'Solar to Battery', 'Solar Wasted', 'Demand'};
    lg = legend(ax, legNames, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';
    lg.FontSize = 16; % Increased legend font size

    % Make X-axis show proper date format without rotating
    ax.XAxis.TickLabelFormat = 'dd/MM/yyyy';
    ax.XAxis.TickLabelRotation = 0;
end

function repKPI = SELECT_12_REPRESENTATIVE_SCENARIOS(KPI)
% Representative scenarios: one per solar-land cap, at a FIXED budget.
%   - land caps >= 400 km2 : REP_BUDGET (lowest budget at which all of them
%                            are feasible and land-binding, in both runs)
%   - low-land benchmark   : REP_BUDGET_LOWLAND (lowest feasible budget)
    REP_BUDGET         = 420e9;
    REP_BUDGET_LOWLAND = 430e9;
    LOWLAND_MAX        = 100;      % km2

    K = KPI(isfinite(KPI.RenewablesPct2050) & isfinite(KPI.TotalCost_AllYears), :);
    areas  = unique(K.MaxAreaSolar);
    repKPI = K([], :);

    for a = areas(:)'
        if a <= LOWLAND_MAX
            B = REP_BUDGET_LOWLAND;
        else
            B = REP_BUDGET;
        end
        j = find(K.MaxAreaSolar == a & abs(K.MaxCost - B) < 1e6, 1);
        if isempty(j)
            warning('Representative scenario missing: land %d km2, budget %.0f x10^9', a, B/1e9);
            continue
        end
        repKPI = [repKPI; K(j, :)]; %#ok<AGROW>
    end

    repKPI = sortrows(repKPI, 'RenewablesPct2050');

    fprintf('\n--- Representative scenarios (budget %.0f x10^9; low-land %.0f x10^9) ---\n', ...
        REP_BUDGET/1e9, REP_BUDGET_LOWLAND/1e9);
    disp(repKPI(:, {'Scenario', 'MaxAreaSolar', 'MaxCost', 'RenewablesPct2050', 'TotalEmissions_AllYears'}));
    fprintf('---------------------------------------------------------------------\n\n');
end
%% ============================================================
%  12 REPRESENTATIVE SCENARIOS UI & PLOTTING FUNCTIONS
% ============================================================

function ANALYZE_12_REPRESENTATIVE_UI(repKPI, scenRoot, gData)
    % Main UI function displaying the 5 specific graphs for the 12 representative scenarios
    
    % Sort just in case it wasn't sorted
    repKPI = sortrows(repKPI, 'RenewablesPct2050');

    % Create main window with white background
    repFig = uifigure('Name', 'Representative Scenarios Dashboard (12 Pareto)', 'Position', [150 100 1300 750], 'Color', 'white');
    tg = uitabgroup(repFig, 'Position', [10 10 1280 730]);

    % --- Tab 1: Average System Cost (Scatter) ---
    tab1 = uitab(tg, 'Title', 'Average System Cost', 'BackgroundColor', 'white');
    ax1 = uiaxes(tab1, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_LCOE_UI(repKPI, scenRoot, ax1);

    % --- Tab 2: Annual System Cost 2050 (Stacked) ---
    tab2 = uitab(tg, 'Title', 'Annual System Cost 2050', 'BackgroundColor', 'white');
    ax2 = uiaxes(tab2, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_COST2050_UI(repKPI, scenRoot, gData.colorsBase, gData.EF_year, ax2);

    % --- Tab 3: Emissions in 2050 (Stacked) ---
    tab3 = uitab(tg, 'Title', 'Emissions 2050', 'BackgroundColor', 'white');
    ax3 = uiaxes(tab3, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_EMISSIONS_2050_UI(repKPI, scenRoot, gData.colorsBase, gData.EF_year, ax3);

    % --- Tab 4: Installed Capacity 2050 (Grouped) ---
    tab4 = uitab(tg, 'Title', 'Installed Capacity 2050', 'BackgroundColor', 'white');
    ax4 = uiaxes(tab4, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_CAPACITY_2050_UI(repKPI, gData.colorsBase, ax4);

    % --- Tab 5: Battery Energy 2050 ---
    tab5 = uitab(tg, 'Title', 'Battery Energy 2050', 'BackgroundColor', 'white');
    ax5 = uiaxes(tab5, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_BATTERY_ENERGY_UI(repKPI, gData.colorsBase, ax5);

    % --- Tab 6: Social LCOE vs Direct LCOE (Scatter) ---
    tab6 = uitab(tg, 'Title', 'Social vs Direct LCOE', 'BackgroundColor', 'white');
    ax6 = uiaxes(tab6, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_SOCIAL_LCOE_UI(repKPI, scenRoot, gData.EF_year, ax6);

        % --- Tab 7: Cost vs Carbon Intensity ---
    tab7 = uitab(tg, 'Title', 'Cost vs Carbon Intensity', 'BackgroundColor', 'white');
    ax7  = uiaxes(tab7, 'Position', [50 50 1180 620], 'Color', 'white');
    PLOT_REP_COST_VS_CI_UI(repKPI, scenRoot, ax7);
end

function PLOT_REP_LCOE_UI(repKPI, scenRoot, ax)
    % Tab 1: Direct average system cost in 2050 = (OPEX + CAPEX) / energy [NIS/kWh]
    % (KPI.LCOE_TargetYear also includes the 200 NIS/t carbon tax - not used here)
    re_sorted = repKPI.RenewablesPct2050;
    y_vals = nan(height(repKPI), 1);
    for s = 1:height(repKPI)
        resFile = fullfile(scenRoot, repKPI.Scenario(s), 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        y2050Idx = 2050 - S.RES.BaseYear + 1;
        C50 = local_costYear(S.RES, y2050Idx);
        y_vals(s) = C50.direct / C50.energy_MWh / 1000;
    end
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    % Plot scatter with dark gray dots
    plot(ax, 1:height(repKPI), y_vals, 'o', 'MarkerEdgeColor', 'none', 'MarkerFaceColor', [0.35 0.35 0.35], 'MarkerSize', 7);
    
    ylabel(ax, 'Average System Cost in 2050 [NIS/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Selected scenarios (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    title(ax, 'Average System Cost in 2050 [NIS/kWh] - selected scenarios', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);
    
    local_applyXReTicks_12(ax, re_sorted);
end

function PLOT_REP_COST2050_UI(repKPI, scenRoot, colorsBase, EF_year, ax)
    % Tab 2: Stacked bar chart of Annual System Cost in 2050 (OPEX, CAPEX, Externalities)
    re_sorted = repKPI.RenewablesPct2050;
    keptCost = zeros(height(repKPI), 11); % 11 components
    
    for s = 1:height(repKPI)
        scName  = repKPI.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        
        y2050Idx = 2050 - RES.BaseYear + 1;
        nYears = size(RES.opCostYearBySource,2);
        
        nSrc = size(RES.opCostYearBySource, 1);
        opex_nuc = 0; capex_nuc = 0;
        if nSrc >= 1
            opex_nuc = RES.opCostYearBySource(1, y2050Idx);
            capex_nuc = sum(RES.buildCostYearBySource(1, :)) / nYears;
        end
        
        C50 = local_costYear(RES, y2050Idx);
        opex_nuc   = C50.opex(1);  capex_nuc   = C50.capex(1);
        opex_solar = C50.opex(2);  capex_solar = C50.capex(2);
        opex_gas   = C50.opex(3);  capex_gas   = C50.capex(3);
        opex_coal  = C50.opex(4);  capex_coal  = C50.capex(4);
        opex_batt  = C50.opex(5);  capex_batt  = C50.capex(5);
        
        capSolar2050 = repKPI.Cap2050_Solar(s); 
        capBatt2050  = repKPI.Cap2050_Battery(s);
        ext2050_NIS  = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050, capBatt2050);

        rowBillion = [opex_nuc, capex_nuc, opex_gas, capex_gas, opex_batt, capex_batt, ...
                      opex_solar, capex_solar, opex_coal, capex_coal, ext2050_NIS] / 1e9;
        keptCost(s, :) = rowBillion;
    end
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:height(repKPI), keptCost, 'stacked', 'EdgeColor', 'none', 'BarWidth', 0.8);
    
    palette = [
        colorsBase.Nuclear; 0.65*colorsBase.Nuclear + 0.35*[1 1 1];
        colorsBase.Gas;     0.65*colorsBase.Gas + 0.35*[1 1 1];
        colorsBase.Batt;    0.65*colorsBase.Batt + 0.35*[1 1 1];
        colorsBase.Solar;   0.65*colorsBase.Solar + 0.35*[1 1 1];
        colorsBase.Coal;    0.65*colorsBase.Coal + 0.35*[1 1 1];
        [0.35 0.35 0.35] % Externalities
    ];
    for k = 1:numel(hb), hb(k).FaceColor = palette(k,:); end

    ylabel(ax, 'Annual cost in 2050 [billion ₪]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 14);
    xlabel(ax, 'Selected scenarios (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 14);
    title(ax, 'Annual system cost in 2050', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 16);
    
    legTxt = {'Nuclear (OPEX)', 'Nuclear (CAPEX)', 'Gas (OPEX)', 'Gas (CAPEX)', ...
              'Battery (OPEX)', 'Battery (CAPEX)', 'Solar (OPEX)', 'Solar (CAPEX)', ...
              'Coal (OPEX)', 'Coal (CAPEX)', 'Externalities'};
    lg = legend(ax, legTxt, 'Location', 'eastoutside');
    lg.Color = 'white'; lg.TextColor = 'black'; lg.FontSize = 12;

    local_applyXReTicks_12(ax, re_sorted);
end

function PLOT_REP_COST_VS_CI_UI(repKPI, scenRoot, ax)
% Average system cost 2050 vs carbon intensity 2050, coloured by %RE 2050.
%   cost = (OPEX + CAPEX) 2050 / energy 2050      [NIS/kWh]  (same as Fig. "Average System Cost")
%   CI   = life-cycle emissions 2050 / energy 2050 [kgCO2e/kWh]
    INCLUDE_CARBON_COST = false;   % true = add the 200 NIS/t carbon cost to the y-axis

    n    = height(repKPI);
    ci   = nan(n,1);
    cost = nan(n,1);
    re   = repKPI.RenewablesPct2050(:);

    for s = 1:n
        resFile = fullfile(scenRoot, repKPI.Scenario(s), 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');  RES = S.RES;
        y = 2050 - RES.BaseYear + 1;
        C = local_costYear(RES, y);

        ci(s) = RES.emitYear(y) / C.energy_MWh;            % t/MWh = kg/kWh
        c_y   = C.direct;
        if INCLUDE_CARBON_COST
            c_y = c_y + sum(RES.extCostYearBySource(:, y)) / RES.P.df_yearly(y);
        end
        cost(s) = c_y / C.energy_MWh / 1000;               % NIS/kWh
    end

    local_styleAxes(ax);
    hold(ax, 'on');
    scatter(ax, ci, cost, 70, re, 'filled', 'MarkerEdgeColor', [0.3 0.3 0.3]);
    colormap(ax, parula);
    cb = colorbar(ax);
    cb.Color = 'black';
    cb.Label.String = '% Renewables (2050)';
    cb.Label.FontWeight = 'bold';

    
    grid(ax, 'on');
    xlabel(ax, 'Carbon intensity 2050 [kgCO_2e/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 16);
     if INCLUDE_CARBON_COST
        ylabel(ax, 'Social average system cost 2050 [NIS/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 16);
        title(ax, 'Social average system cost (direct + carbon cost) 2050 vs Carbon Intensity 2050', ...
            'Color', 'black', 'FontWeight', 'bold', 'FontSize', 18);
    else
        ylabel(ax, 'Average system cost (2050) [NIS/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 16);
        title(ax, 'Average system cost 2050 vs Carbon Intensity 2050', ...
            'Color', 'black', 'FontWeight', 'bold', 'FontSize', 18);
    end
    title(ax, 'Average system cost 2050 vs Carbon Intensity 2050', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 18);
end

function PLOT_REP_EMISSIONS_2050_UI(repKPI, scenRoot, colorsBase, EF_year, ax)
    % Tab 3: Emissions in 2050 by source
    re_sorted = repKPI.RenewablesPct2050;
    Y_stack_tCO2e = zeros(height(repKPI), 5);
    srcNames = ["Nuclear", "Solar", "Gas", "Coal", "Battery"];
    
    for s = 1:height(repKPI)
        scName  = repKPI.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile), continue; end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        
        y2050Idx = 2050 - RES.BaseYear + 1;
        if y2050Idx > size(RES.genYear, 2), continue; end
        
        G = local_genForEmissions(RES);
        G = G(:, y2050Idx);
        emisBySrc =(G .* EF_year(:, y2050Idx)).';
        
        % Pad to 5 sources if nuclear or battery is missing in arrays
        emisPadded = zeros(1, 5);
        emisPadded(1:length(emisBySrc)) = emisBySrc;
        Y_stack_tCO2e(s, :) = emisPadded;
    end
    
    Y_stack_Mt = Y_stack_tCO2e / 1e6;
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    hb = bar(ax, 1:height(repKPI), Y_stack_Mt, 'stacked', 'EdgeColor', 'none', 'BarWidth', 0.8);
    local_applyColors(hb, srcNames, colorsBase);

    ylabel(ax, 'Emissions in 2050 [MtCO_2e]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Scenarios (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    title(ax, 'Emissions in 2050 by source (Selected scenarios)', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);
    
    % Create legend ignoring zero-emission sources to match the user's graph
    lg = legend(ax, cellstr(srcNames), 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white'; lg.TextColor = 'black'; lg.FontSize = 16;

    local_applyXReTicks_12(ax, re_sorted);
end

function PLOT_REP_CAPACITY_2050_UI(repKPI, colorsBase, ax)
    % Tab 4: Installed capacity 2050 (Grouped/Stacked: Generation vs Battery)
    re_sorted = repKPI.RenewablesPct2050;
    
    % Generation stack: Nuclear, Gas, Solar, Coal
    Y_gen = [repKPI.Cap2050_Nuclear, repKPI.Cap2050_Gas, repKPI.Cap2050_Solar, repKPI.Cap2050_Coal] / 1000;
    Y_batt = repKPI.Cap2050_Battery / 1000;
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    % Use manual X offsets to create grouped/stacked illusion
    x_gen = (1:height(repKPI)) - 0.2;
    x_batt = (1:height(repKPI)) + 0.2;
    
    hb_gen = bar(ax, x_gen, Y_gen, 0.4, 'stacked', 'EdgeColor', 'none');
    hb_gen(1).FaceColor = colorsBase.Nuclear;
    hb_gen(2).FaceColor = colorsBase.Gas;
    hb_gen(3).FaceColor = colorsBase.Solar;
    hb_gen(4).FaceColor = colorsBase.Coal;
    
    bar(ax, x_batt, Y_batt, 0.4, 'FaceColor', colorsBase.Batt, 'EdgeColor', 'none');

    ylabel(ax, 'Installed capacity in 2050 [GW]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Renewables blocks (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    title(ax, 'Installed capacity in 2050 by source (GW), Battery 4H Model', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);
    
    legTxt = {'Nuclear', 'Gas', 'Solar', 'Coal', 'Battery (4H Model, charge from solar)'};
    lg = legend(ax, legTxt, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white'; lg.TextColor = 'black'; lg.FontSize = 16;

    local_applyXReTicks_12(ax, re_sorted);
    ax.XLim = [0.2, height(repKPI) + 0.8];
end

function PLOT_REP_BATTERY_ENERGY_UI(repKPI, colorsBase, ax)
    % Tab 5: Battery Energy Capacity 2050 [GWh]
    re_sorted = repKPI.RenewablesPct2050;
    Y_batt_energy = (repKPI.Cap2050_Battery * 4) / 1000; % Convert MW to GWh
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    bar(ax, 1:height(repKPI), Y_batt_energy, 0.7, 'FaceColor', colorsBase.Batt, 'EdgeColor', 'none');

    ylabel(ax, 'Battery energy capacity in 2050 [GWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Scenarios (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    title(ax, 'Battery capacity in 2050 (4-hour model)', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);

    local_applyXReTicks_12(ax, re_sorted);
end

function local_applyXReTicks_12(ax, re_sorted)
    % Helper function: explicitly show every tick for the 12 selected scenarios
    n = numel(re_sorted);
    xticks(ax, 1:n);
    % Format to exactly 2 decimal places to match user's request (e.g., 11.20%)
    xticklabels(ax, arrayfun(@(v) sprintf('%.2f%%', v), re_sorted, 'UniformOutput', false));
    xtickangle(ax, 45);
    ax.XAxis.Color = 'black';
    ax.YAxis.Color = 'black';
end
function PLOT_REP_SOCIAL_LCOE_UI(repKPI, scenRoot, EF_year, ax)
    % Tab 6: Scatter plot comparing Direct LCOE to Total LCOE (including externalities)
    re_sorted = repKPI.RenewablesPct2050;
    
    y_direct_lcoe = nan(height(repKPI), 1);
    y_total_lcoe = zeros(height(repKPI), 1);
    
    for s = 1:height(repKPI)
        scName  = repKPI.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            y_total_lcoe(s) = NaN;              % file missing -> not plotted
            continue; 
        end
        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;
        
        y2050Idx = 2050 - RES.BaseYear + 1;
        nYears = size(RES.opCostYearBySource, 2);
        
        % Calculate direct costs for 2050 (Restored original smoothing logic)
        C50 = local_costYear(RES, y2050Idx);
        directCost2050 = C50.direct;
        y_direct_lcoe(s) = directCost2050 / C50.energy_MWh / 1000;
        
        % Calculate externalities for 2050 (Restored original external helper)
        capSolar2050 = repKPI.Cap2050_Solar(s); 
        capBatt2050  = repKPI.Cap2050_Battery(s);
        ext2050_NIS  = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050, capBatt2050);
        
        % Calculate Total LCOE using the cost ratio
        y_total_lcoe(s) = (directCost2050 + ext2050_NIS) / C50.energy_MWh / 1000;
    end
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    % Plot the Direct LCOE (dark gray) for comparison
    plot(ax, 1:height(repKPI), y_direct_lcoe, 'o', 'MarkerEdgeColor', 'none', 'MarkerFaceColor', [0.35 0.35 0.35], 'MarkerSize', 8);
    
    % Plot the Total LCOE (orange/red) 
    plot(ax, 1:height(repKPI), y_total_lcoe, 'o', 'MarkerEdgeColor', 'none', 'MarkerFaceColor', [0.85 0.32 0.09], 'MarkerSize', 8);
    
    % Formatting
    ylabel(ax, 'Cost in 2050 [NIS/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Selected scenarios (sorted by %RE 2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    title(ax, 'Total LCOE vs Direct LCOE in 2050', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);
    
    lg = legend(ax, {'Direct LCOE (CAPEX+OPEX)', 'Total LCOE (Direct + Externalities)'}, 'Location', 'northeast');
    lg.Color = 'white'; lg.TextColor = 'black'; lg.FontSize = 16;
    local_applyXReTicks_12(ax, re_sorted);
end

function PLOT_CUSTOM_BATTERY_RANGE_UI(RES, gData, ax, startDt, endDt, scName)
    % Plots the battery energy level (State of Charge) for a specific date range

    if startDt > endDt
        cla(ax);
        title(ax, 'Error: Start Date must be before or equal to End Date', 'Color', 'red');
        return;
    end

    dtAll = local_modelDates(gData.startYr, gData.T, gData.yearLen);
    
    % Include the full end day up to 23:59
    endDtFull = endDt + hours(23);
    mask = (dtAll >= startDt) & (dtAll <= endDtFull);

    if ~any(mask)
        cla(ax);
        title(ax, 'No data available for the selected date range.', 'Color', 'red');
        return;
    end

    if ~isfield(RES, 'E')
        cla(ax);
        title(ax, 'Battery energy data (RES.E) not found in results.', 'Color', 'red');
        return;
    end

    % Extract Battery Energy and convert from MWh to GWh
    E_m = RES.E(mask) / 1000;
    dt_m = dtAll(mask);

    % Plotting
    cla(ax);
    local_styleAxes(ax);
    hold(ax, 'on');

    plot(ax, dt_m, E_m, 'Color', gData.colorsBase.Batt, 'LineWidth', 1.2);

    % Calculate max capacity in GWh dynamically
    maxCapGWh = max(RES.E) / 1000;

    % Try to get RE% from global KPI_Data if available in workspace for title
    reStr = '';
    try
        KPI_Data = evalin('base', 'KPI_Data');
        idx = find(KPI_Data.Scenario == string(scName), 1);
        if ~isempty(idx)
            reStr = sprintf(' (RE=%.2f%%)', KPI_Data.RenewablesPct2050(idx));
        end
    catch
        % Ignore and keep empty if KPI_Data is not loaded in base workspace
    end

    % Formatting with enlarged fonts
    ylabel(ax, 'Battery energy level [GWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    xlabel(ax, 'Date (2050)', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 18);
    
    titleStr = sprintf('Battery energy level in 2050%s', reStr);
    title(ax, titleStr, 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 20);

    % Legend setup showing the calculated capacity
    legStr = sprintf('Battery energy (Capacity: %.2f GWh)', maxCapGWh);
    lg = legend(ax, {legStr}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white';
    lg.TextColor = 'black';
    lg.FontSize = 16;

    % Format X-axis to match the requested image format (e.g., "Jan 01")
    ax.XAxis.TickLabelFormat = 'MMM dd';
    ax.XAxis.TickLabelRotation = 0;
end

function PLOT_LCOE_OVER_TIME_UI(RES, gData, ax)
    % Plots the change in Direct and Total LCOE over the years 2023-2050 for a specific scenario
    
    if ~isfield(RES, 'lcoeYear_kWh')
        title(ax, 'No LCOE over time data found in results.', 'Color', 'red');
        return;
    end
    
    nYears = size(RES.lcoeYear_kWh, 2);
    years = gData.startYr : (gData.startYr + nYears - 1);
    
    direct_lcoe = zeros(1, nYears);
    total_lcoe  = zeros(1, nYears);
    
    for y = 1:nYears
        Cy = local_costYear(RES, y);
        direct_lcoe(y) = Cy.direct / Cy.energy_MWh / 1000;

        capSolar_y = RES.capYear(2, y);
        capBatt_y  = RES.capYear(5, y);
        ext_y_NIS  = local_externalities_2050_NIS(RES, gData.EF_year, y, capSolar_y, capBatt_y);

        total_lcoe(y) = (Cy.direct + ext_y_NIS) / Cy.energy_MWh / 1000;
    end
    
    local_styleAxes(ax);
    hold(ax, 'on');
    
    % Plot lines and points
    plot(ax, years, direct_lcoe, '-o', 'Color', [0.35 0.35 0.35], 'LineWidth', 2, 'MarkerFaceColor', [0.35 0.35 0.35], 'MarkerSize', 6);
    plot(ax, years, total_lcoe, '-o', 'Color', [0.85 0.32 0.09], 'LineWidth', 2, 'MarkerFaceColor', [0.85 0.32 0.09], 'MarkerSize', 6);
    
    ylabel(ax, 'LCOE [NIS/kWh]', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 14);
    xlabel(ax, 'Year', 'FontWeight', 'bold', 'Color', 'black', 'FontSize', 14);
    title(ax, 'Direct vs Total LCOE Over Time (2023-2050)', 'Color', 'black', 'FontWeight', 'bold', 'FontSize', 16);
    
    lg = legend(ax, {'Direct LCOE (CAPEX+OPEX)', 'Total LCOE (Direct + Externalities)'}, 'Location', 'northoutside', 'Orientation', 'horizontal');
    lg.Color = 'white'; lg.TextColor = 'black'; lg.FontSize = 12;
    
    xticks(ax, years(1:2:end)); 
    xtickangle(ax, 45);
end

function G = local_genForEmissions(RES)
% Annual energy per source used for LIFE-CYCLE EMISSIONS [MWh].
% Same as genYear, except solar = all generated solar energy
% (to grid + to battery + curtailed) = cf*K, consistent with the optimization objective.
    G = RES.genYear;
    if isfield(RES,'ChB') && isfield(RES,'Dump')
        yearLen = 8760;
        nY = size(G,2);
        ChB  = RES.ChB(:);  Dump = RES.Dump(:);
        for y = 1:nY
            rng = (y-1)*yearLen + (1:yearLen);
            G(2,y) = G(2,y) + sum(ChB(rng)) + sum(Dump(rng));
        end
    end
end

function C = local_costYear(RES, y)
    df = RES.P.df_yearly(y);
    C.opex       = RES.opCostYearBySource(:, y)    / df;
    C.capex      = RES.buildCostYearBySource(:, y) / df;
    C.direct     = sum(C.opex) + sum(C.capex);
    C.energy_MWh = max(1, RES.elecYear(y));
end

function dtAll = local_modelDates(startYr, T, yearLen)
% Calendar date of every model hour. Each model year has yearLen (8760) hours and
% repeats the 2023 weather year, so every year follows a non-leap calendar.
    if nargin < 3, yearLen = 8760; end
    h     = 0:T-1;
    yy    = startYr + floor(h / yearLen);
    ref   = datetime(2023, 1, 1) + hours(mod(h, yearLen));
    dtAll = datetime(yy, month(ref), day(ref), hour(ref), 0, 0);
end