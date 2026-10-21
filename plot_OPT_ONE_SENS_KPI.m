% ============================================================
%  plot_OPT_ONE_SENS_KPI.m
% ============================================================

clear; clc; close all;

%% ---------- ONE TIME INPUTS: DEMAND, CF, EMISSION FACTORS ----------
xlsFile   = 'C:\Users\nhmu1\OneDrive\Desktop\עבודה עוזר מחקר\MODEL optimization-Itay\ROTH 1 Model - Itay.xlsx';
sheetName = 'ROTH 1.0';
rangeDem  = 'J6:J245285';        % Demand
startYr   = 2023;
yearLen   = 8760;

Demand = xlsread(xlsFile, sheetName, rangeDem);
Demand = Demand(:);
T      = numel(Demand);
nYears = floor(T / yearLen);

% Solar CF
cf_single = readmatrix(xlsFile, 'Sheet', sheetName, 'Range', 'L6:L8765');
cf_single(isnan(cf_single)) = 0;
cf = repmat(cf_single, ceil(T / 8760), 1);
cf = cf(1:T);

% Solar EF per year
rangeSolarEF = 'C3:C36';
cSolar_year  = readmatrix(xlsFile, 'Sheet', 'PVEmissions', 'Range', rangeSolarEF);
cSolar_year  = cSolar_year(:);
cSolar_year  = cSolar_year(1:nYears);
cSolar_t     = repelem(cSolar_year, yearLen);
cSolar_t     = cSolar_t(1:T);

% Battery EF per year
rangeBattEF = 'C2:C35';
cBatt_year  = readmatrix(xlsFile, 'Sheet', 'StoargeEmission', 'Range', rangeBattEF);
cBatt_year  = cBatt_year(:);
cBatt_year  = cBatt_year(1:nYears);
cBatt_t     = repelem(cBatt_year, yearLen);
cBatt_t     = cBatt_t(1:T);

% ---------- Emission factors by source and by year (order: [Nuclear, Solar, Gas, Coal, Battery]) ----------
% NOTE: Use the same units as your model uses for emissions per MWh (typically tCO2e/MWh).

% If you already have constants for nuclear/gas/coal in your scenario runner, paste them here.
% Otherwise set them explicitly below.
c = [0.012;0.03695;0.486;0.9;0.04]; % tCO2 / MWh
cNuc  = c(1);
cGas  = c(3);
cCoal = c(4);


EF_year = zeros(5, nYears);
EF_year(1,:) = cNuc;
EF_year(2,:) = cSolar_year(:).';
EF_year(3,:) = cGas;
EF_year(4,:) = cCoal;
EF_year(5,:) = cBatt_year(:).';

srcNames = ["Nuclear","Solar","Gas","Coal","Battery"];



%% ---------- A) UI hourly plot 6 (RUN ONCE) ----------
UI_PLOT_HOURLY_FROM_RESULTS_HEAVY(Demand, startYr, yearLen, false);

%% ---------- 1) Select KPI_summary file (MAT or CSV) ----------
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

% ---------- 2) Load KPI table ----------
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

fprintf('Loaded KPI table with %d scenarios and %d columns.\n', height(KPI), width(KPI));

% ---------- 3) Output directory ----------
figDir = fullfile(fp, 'figures_opt_one_sens');
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

% ---------- 4) Shared RE bins and shared colors ----------
if iscell(KPI.Scenario) || ischar(KPI.Scenario)
    KPI.Scenario = string(KPI.Scenario);
end
if any(KPI.Scenario == "S101_Special")
    KPI = KPI(KPI.Scenario ~= "S101_Special", :);
end

re_all = KPI.RenewablesPct2050(:);
re_all = re_all(isfinite(re_all));
if isempty(re_all)
    error('KPI.RenewablesPct2050 has no finite values.');
end

% RE ticks based on the full range, in 10 "blocks"
reTargets = linspace(min(re_all), max(re_all), 11);

% Shared palette (soft) + your rules: coal purple, waste gray
colorsBase.Nuclear = [0.25 0.35 0.60]; % soft navy / steel-blue
colorsBase.Gas   = [0.75 0.25 0.25];
colorsBase.Batt  = [0.30 0.65 0.40];
colorsBase.Solar = [0.90 0.75 0.25];
colorsBase.Coal  = [0.55 0.35 0.65]; % purple-ish
colorsBase.Waste = [0.60 0.60 0.60]; % gray

% ---------- 5) Locate scenarios folder once ----------
scenRoot = locateScenariosFolder(fullKpiFile);

%% ---------- Figure 1 (Mesh) at the end ----------
fig1 = figure('Color','w','Position',[220 160 1100 720]);
MESH3D_RESULTS(KPI);
outFig1 = fullfile(figDir, 'F01_Mesh_Cost_Land_RE2050.png');
saveas(fig1, outFig1);
fprintf('Figure 1 saved to:\n  %s\n', outFig1);
%% ----------  Figure 2: Demand-cover stack in 2050 (ALL scenarios) ----------
fig2 = PLOT_DEMAND_COVER_STACK_2050_ALL(KPI, scenRoot, reTargets, colorsBase);
outFig2 = fullfile(figDir, 'F02_DemandCover2050_AllScenarios.png');
saveas(fig2, outFig2);
fprintf('Figure 2 saved to:\n  %s\n', outFig2);

%% ----------  Figure 3: Annual cost 2050 (OPEX + CAPEX) (ALL scenarios) ----------
fig3 = PLOT_COST2050_STACK_BY_SOURCE_OPEX_CAPEX_ALL(KPI, scenRoot, colorsBase, reTargets, [], EF_year);

outFig3 = fullfile(figDir, 'F03_AnnualCost2050_OPEX_CAPEX_AllScenarios.png');
saveas(fig3, outFig3);
fprintf('Figure 3 saved to:\n  %s\n', outFig3);

%% ----------  Figure 4: LCOE scatter (ALL scenarios) ----------
fig4 = PLOT_LCOE2050_EFFECTIVE_SCATTER_ALL(KPI, scenRoot, reTargets, EF_year);
outFig4 = fullfile(figDir, 'F04_LCOE_AllScenarios.png');
saveas(fig4, outFig4);
fprintf('Figure 4 saved to:\n  %s\n', outFig4);

%% ----------  Figure 4b: Min LCOE per 0.1% RE (separate figure) ----------
%[fig4b, scenKeepB] = PLOT_LCOE2050_MIN_PER_REBIN(KPI, scenRoot, 0.1, EF_year);
[fig4b, scenKeepB] = PLOT_LCOE2050_SELECTED_SCENARIOS(KPI, scenRoot, 0.1, EF_year);

outFig4b = fullfile(figDir, 'F04b_LCOE_MinPerDeltaRE.png');
saveas(fig4b, outFig4b);
fprintf('Figure 4b saved to:\n  %s\n', outFig4b);

%% ----------  Figure 5: Installed capacity 2050 (ALL scenarios) ----------
fig5 = PLOT_CAPACITY2050_STACK_BY_SOURCE_ALL(KPI, colorsBase, reTargets);
outFig5 = fullfile(figDir, 'F05_Capacity2050_Stack_AllScenarios.png');
saveas(fig5, outFig5);
fprintf('Figure 5 saved to:\n  %s\n', outFig5);

%% b's figs
fig2b = PLOT_DEMAND_COVER_STACK_2050_ALL(KPI, scenRoot, reTargets, colorsBase, scenKeepB);
%fig3b = PLOT_COST2050_STACK_BY_SOURCE_OPEX_CAPEX_ALL(KPI, scenRoot, colorsBase, reTargets, scenKeepB);
%%
fig3b = PLOT_COST2050_STACK_BY_SOURCE_OPEX_CAPEX_ALL(KPI, scenRoot, colorsBase, reTargets, scenKeepB, EF_year);
%%
fig5b = PLOT_CAPACITY2050_STACK_BY_SOURCE_ALL(KPI, colorsBase, reTargets, scenKeepB);


%% ---------- Figure 6: Pearson correlation heatmaps ----------
fig6_all = PLOT_PEARSON_CORR_HEATMAP_KPI(KPI, figDir, "All", []);
fig6_b   = PLOT_PEARSON_CORR_HEATMAP_KPI(KPI, figDir, "Selected Scenarios", scenKeepB);

%% ---------- Figure 7: Total emissions (all years) stacked by source ----------
fig7  = PLOT_EMISSIONS_ALLYEARS_STACK_BY_SOURCE_ALL(KPI, scenRoot, reTargets, colorsBase, [], EF_year, srcNames);
outFig7 = fullfile(figDir, 'F07_Emissions_AllYears_Stack_BySource_AllScenarios.png');
saveas(fig7, outFig7);

%%
fig7c = PLOT_EMISSIONS_2050_STACK_BY_SOURCE_ALL( ...
    KPI, scenRoot, reTargets, colorsBase, scenKeepB, EF_year);

outFig7c = fullfile(figDir, 'F07C_Emissions_2050_Stack_BySource_Selected.png');
saveas(fig7c, outFig7c);
fprintf('Figure 7C saved to:\n  %s\n', outFig7c);
%%
fig7d_all = PLOT_EMISSIONS_2050_STACK_BY_SOURCE_ALL_SCENARIOS( ...
    KPI, scenRoot, reTargets, colorsBase, EF_year);

outFig7d_all = fullfile(figDir, 'F07C_Emissions_2050_Stack_BySource_ALL.png');
saveas(fig7d_all, outFig7d_all);
fprintf('Figure 7D (ALL) saved to:\n  %s\n', outFig7d_all);

%%
figCI = PLOT_COST_VS_CARBON_INTENSITY_SCATTER_ALL(KPI, scenRoot, colorsBase, reTargets, [], EF_year);
figCI_B = PLOT_COST_VS_CARBON_INTENSITY_SCATTER_ALL(KPI, scenRoot, colorsBase, reTargets, scenKeepB, EF_year);
%%
% Battery-only (ALL scenarios)
figBatt = PLOT_BATTERY2050_GWH_BAR_ALL(KPI, colorsBase, reTargets, []);
outFigBatt = fullfile(figDir, 'F05b_Battery2050_GWh_AllScenarios.png');
saveas(figBatt, outFigBatt);
%%
% Battery-only (Selected scenarios)
figBattB = PLOT_BATTERY2050_GWH_BAR_ALL(KPI, colorsBase, reTargets, scenKeepB);
outFigBattB = fullfile(figDir, 'F05c_Battery2050_GWh_Selected.png');
saveas(figBattB, outFigBattB);


%%
outCsv = fullfile(figDir, 'BatteryDischargeTime2050_Selected.csv');
T_batt = EXPORT_BATTERY_DISCHARGE_TIME_2050_CSV(KPI, scenRoot, scenKeepB, outCsv);

%%
figBattTS = PLOT_BATTERY_ENERGY_2050_TIMESERIES_SELECTED(KPI, scenRoot, scenKeepB, colorsBase);
outFigBattTS = fullfile(figDir, 'F08_BatteryEnergy2050_TimeSeries_SelectedFirstAbove90.png');
saveas(figBattTS, outFigBattTS);
fprintf('Battery 2050 time-series figure saved to:\n  %s\n', outFigBattTS);

%%
[figCapLine, figCapStack, scUsed] = UI_PLOT_CAPACITY_GROWTH_STEPS_FROM_RESULTS_HEAVY( ...
    scenRoot, [], colorsBase, startYr);

outA = fullfile(figDir, 'F_CAP_GROWTH_A_LineSteps.png');
outC = fullfile(figDir, 'F_CAP_GROWTH_C_StackedSteps.png');
saveas(figCapLine, outA);
saveas(figCapStack, outC);
fprintf('Capacity growth figures saved:\n  %s\n  %s\n', outA, outC);
fprintf('Scenario used: %s\n', scUsed);


%% ============================================================
%  LOCAL FUNCTIONS
% ============================================================

function scenRoot = locateScenariosFolder(fullKpiFile)
% Locate scenarios folder given KPI file path (expects KPI in ...\tables\)
kpiDir = fileparts(fullKpiFile);
runDir = fileparts(kpiDir);
cand1  = fullfile(runDir, 'scenarios');

if isfolder(cand1)
    scenRoot = cand1;
    return;
end

% Fallback: try to search upward a bit
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

function fig = PLOT_DEMAND_COVER_STACK_2050_ALL(KPI, scenRoot, reTargets, colorsBase, scenKeep)
% PLOT_DEMAND_COVER_STACK_2050_ALL
% Demand coverage in 2050 for scenarios (stacked annual energy).
% Uses RES fields:
% - RES.genYear       [nSources x nYears] annual generation by source [MWh]
% - RES.demYear       [nYears x 1] or [1 x nYears] annual demand [MWh]
% - RES.Dump2050_MWh  scalar [MWh]
%
% Supports optional Nuclear (source #1). If present in any scenario, it will
% be stacked FIRST (bottom). Otherwise, behavior is identical to the previous version.
%
% Legend labels:
% Nuclear (optional), Gas, Battery (Charge from solar), Solar to grid, Coal, Waste (from Solar), Demand

    if nargin < 5
        scenKeep = [];
    end

    if iscell(KPI.Scenario) || ischar(KPI.Scenario)
        KPI.Scenario = string(KPI.Scenario);
    end
    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end

    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Ensure Nuclear color exists (fallback)
    if ~isfield(colorsBase, 'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    keptRE = zeros(0,1);

    % We will store: [Nuclear, Gas, Batt, Solar, Coal, Waste]
    Y_MWh = zeros(0,6);
    dem2050_MWh = zeros(0,1);

    hasNuclearAny = false;

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            warning('Missing results_heavy.mat for %s, skipping.', scName);
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;

        if ~isfield(RES,'genYear') || ~isfield(RES,'demYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        y2050 = 2050 - RES.BaseYear + 1;
        if y2050 < 1 || y2050 > size(RES.genYear,2)
            continue;
        end

        % Source order: 1 Nuclear | 2 Solar | 3 Gas | 4 Coal | 5 Battery
        nRows = size(RES.genYear,1);

        nuc   = 0;
        solar = 0;
        gas   = 0;
        coal  = 0;
        batt  = 0;

        if nRows >= 1 && isfinite(RES.genYear(1, y2050))
            nuc = RES.genYear(1, y2050);
            hasNuclearAny = true;
        end
        if nRows >= 2 && isfinite(RES.genYear(2, y2050)), solar = RES.genYear(2, y2050); end
        if nRows >= 3 && isfinite(RES.genYear(3, y2050)), gas   = RES.genYear(3, y2050); end
        if nRows >= 4 && isfinite(RES.genYear(4, y2050)), coal  = RES.genYear(4, y2050); end
        if nRows >= 5 && isfinite(RES.genYear(5, y2050)), batt  = RES.genYear(5, y2050); end

        dump = 0;
        if isfield(RES,'Dump2050_MWh') && isfinite(RES.Dump2050_MWh)
            dump = RES.Dump2050_MWh;
        end

        dy = RES.demYear(:);
        if numel(dy) >= y2050
            dem = dy(y2050);
        else
            dem = NaN;
        end

        keptRE(end+1,1) = re_sorted(s); %#ok<AGROW>
        Y_MWh(end+1,:) = [nuc, gas, batt, solar, coal, dump]; %#ok<AGROW>
        dem2050_MWh(end+1,1) = dem; %#ok<AGROW>
    end

    if isempty(keptRE)
        fig = figure('Color','w');
        warning('No scenarios available for Demand Coverage figure (all skipped).');
        return;
    end

    % If Nuclear never appears, drop it to keep EXACT previous behavior/order
    if ~hasNuclearAny
        % previous order was: [Gas, Batt, Solar, Coal, Waste]
        Y_MWh = Y_MWh(:, 2:end);
    end

    % ---- Convert to TWh ----
    Y = Y_MWh / 1e6;              % TWh
    dem2050_TWh = dem2050_MWh / 1e6;

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    x = 1:size(Y,1);
    hb = bar(ax, x, Y, 'stacked', 'EdgeColor', 'none');

    % Colors + legend (dynamic based on whether Nuclear exists)
    if hasNuclearAny
        hb(1).FaceColor = colorsBase.Nuclear;
        hb(2).FaceColor = colorsBase.Gas;
        hb(3).FaceColor = colorsBase.Batt;
        hb(4).FaceColor = colorsBase.Solar;
        hb(5).FaceColor = colorsBase.Coal;

        if isfield(colorsBase,'Waste')
            hb(6).FaceColor = colorsBase.Waste;
        else
            hb(6).FaceColor = [0.35 0.35 0.35];
        end

        legBars = { ...
            'Nuclear', ...
            'Gas', ...
            'Battery (Charge from solar)', ...
            'Solar to grid', ...
            'Coal', ...
            'Waste  Solar', ...
            'Demand' ...
        };
    else
        hb(1).FaceColor = colorsBase.Gas;
        hb(2).FaceColor = colorsBase.Batt;
        hb(3).FaceColor = colorsBase.Solar;
        hb(4).FaceColor = colorsBase.Coal;

        if isfield(colorsBase,'Waste')
            hb(5).FaceColor = colorsBase.Waste;
        else
            hb(5).FaceColor = [0.35 0.35 0.35];
        end

        legBars = { ...
            'Gas', ...
            'Battery (Charge from solar)', ...
            'Solar to grid', ...
            'Coal', ...
            'Waste  Solar', ...
            'Demand' ...
        };
    end

    % Demand line (median across scenarios for robustness)
    if any(isfinite(dem2050_TWh))
        demLine = median(dem2050_TWh(isfinite(dem2050_TWh)));
        plot(ax, [1 numel(x)], [demLine demLine], 'k-', 'LineWidth', 1.5);
    end

    ylabel(ax, 'Energy in 2050 [TWh]', 'FontWeight','bold');
    xlabel(ax, 'Scenarios (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, '2050 Demand coverage by source (All scenarios)');

    legend(ax, legBars, 'Location','northoutside', 'Orientation','horizontal');

    % Remove X grid only
    ax.XGrid = 'off';
    ax.YGrid = 'on';

    % Show explicit Y numbers (no exponent)
    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%.0f');

    % Y grid/ticks every 25 TWh
    yl = ylim(ax);
    y0 = 25 * floor(yl(1)/25);
    y1 = 25 * ceil(yl(2)/25);
    yticks(ax, y0:25:y1);

    % Custom tick rule for this figure
    applyScenarioIndexTicks(ax, keptRE);
end

function applyScenarioIndexTicks(ax, re_sorted)
% Show ticks at scenario #1, #3, #last, and every 10th scenario index between anchors.

    n = numel(re_sorted);
    if n == 0
        return;
    end

    anchors = unique([1, min(3,n), n], 'stable');
    tickIdx = anchors;

    for k = 1:numel(anchors)-1
        a = anchors(k);
        b = anchors(k+1);
        extra = (ceil((a+1)/10)*10):10:(b-1);
        tickIdx = [tickIdx, extra]; %#ok<AGROW>
    end

    tickIdx = unique(tickIdx);
    tickIdx = tickIdx(tickIdx >= 1 & tickIdx <= n);

    xticks(ax, tickIdx);
    lbls = strings(size(tickIdx));
    for i = 1:numel(tickIdx)
        lbls(i) = sprintf('%.1f', re_sorted(tickIdx(i)));
    end
    xticklabels(ax, lbls);
    xtickangle(ax, 45);
end



function applyReBlockTicks(ax, re_sorted, deltaPct)
% applyReBlockTicks
% X-axis ticks shown only when %RE changes by >= deltaPct
%
% Inputs:
%   ax        - axes handle
%   re_sorted - vector of RenewablesPct2050 sorted ascending
%   deltaPct  - minimal change to show a new tick (e.g. 0.1)

n = numel(re_sorted);
if n == 0
    return;
end

% Always include first scenario
tickIdx = 1;
tickVal = re_sorted(1);

lastVal = re_sorted(1);

for i = 2:n
    if (re_sorted(i) - lastVal) >= deltaPct
        tickIdx(end+1,1) = i;          %#ok<AGROW>
        tickVal(end+1,1) = re_sorted(i); %#ok<AGROW>
        lastVal = re_sorted(i);
    end
end

% Apply ticks
xticks(ax, tickIdx);
xticklabels(ax, arrayfun(@(v) sprintf('%.1f%%', v), tickVal, ...
    'UniformOutput', false));

xtickangle(ax, 45);

end


function fig = PLOT_LCOE2050_EFFECTIVE_SCATTER_ALL(KPI, scenRoot, reTargets, EF_year)
% Scatter of effective LCOE in 2050 (ALL scenarios), including 2050 externalities:
% - Climate (SCC * emissions2050)
% - EOL annual provision (solar + battery)

    KPI.Scenario = string(KPI.Scenario);

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end
    if nargin < 4 || isempty(EF_year)
        error('EF_year must be provided.');
    end

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Require capacities for EOL provision
    vn = string(K.Properties.VariableNames);
    if ~ismember("Cap2050_Solar", vn) || ~ismember("Cap2050_Battery", vn)
        error('KPI must contain Cap2050_Solar and Cap2050_Battery for externalities-based LCOE.');
    end

    y2050_vals = nan(height(K),1);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S, 'RES')
            continue;
        end
        RES = S.RES;

        if ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource') || ...
           ~isfield(RES,'elecYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        nYears = size(RES.opCostYearBySource, 2);
        y2050Idx = 2050 - RES.BaseYear + 1;

        if y2050Idx < 1 || y2050Idx > nYears
            continue;
        end
        if y2050Idx > numel(RES.elecYear)
            continue;
        end

        % Annualized CAPEX (NIS/year)
        capexAvg_NIS_per_year = sum(RES.buildCostYearBySource(:), 'all') / nYears;

        % OPEX in 2050 (NIS/year)
        opex2050_NIS_per_year = sum(RES.opCostYearBySource(:, y2050Idx), 1);

        % Electricity in 2050 (MWh/year)
        elec2050_MWh = RES.elecYear(y2050Idx);
        if ~isfinite(elec2050_MWh) || elec2050_MWh <= 0
            continue;
        end

        % Externalities in 2050 (NIS/year)
        capSolar2050_MW = K.Cap2050_Solar(s);
        capBatt2050_MW  = K.Cap2050_Battery(s);

        ext2050_NIS_per_year = local_externalities_2050_NIS( ...
            RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);

        if ~isfinite(ext2050_NIS_per_year)
            ext2050_NIS_per_year = 0;
        end

        % LCOE in 2050 (NIS/kWh)
        y2050_vals(s) = (opex2050_NIS_per_year + capexAvg_NIS_per_year + ext2050_NIS_per_year) ...
            / (elec2050_MWh * 1000);
    end

    ok = isfinite(y2050_vals) & isfinite(re_sorted);
    y = y2050_vals(ok);
    re_used = re_sorted(ok);

    fig = figure('Color','w','Position',[220 160 1200 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    plot(ax, 1:numel(y), y, 'o', 'MarkerSize', 5, ...
        'MarkerFaceColor', [0.4 0.4 0.4], 'MarkerEdgeColor', [0.4 0.4 0.4]);

    ylabel(ax, 'LCOE 2050 [NIS/kWh]', 'FontWeight','bold', 'FontSize', 16);
    xlabel(ax, 'Renewables blocks (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'Effective LCOE in 2050 (incl. climate + EOL externalities)');

    applyReBlockTicks(ax, re_used, 0.1);
end

function fig = PLOT_COST2050_STACK_BY_SOURCE_OPEX_CAPEX_ALL(KPI, scenRoot, colorsBase, reTargets, scenKeep, EF_year)
% PLOT_COST2050_STACK_BY_SOURCE_OPEX_CAPEX_ALL
% Annual cost in 2050 (stacked, OPEX + avg CAPEX) plus NEW externalities (ex post):
% - Climate externality in 2050: Emissions2050[tCO2e] * SCC[₪/tCO2e]
% - End-of-life (EOL) annual provision in 2050:
%     Cap2050_Solar[MW] * EOL_Solar[₪/MW] / LifeSolar[yr] +
%     Cap2050_Battery[MW] * EOL_Batt[₪/MW] / LifeBatt[yr]
%
% IMPORTANT:
% - Externalities are computed ONLY via local_externalities_2050_NIS(...)
%   so changing parameters inside that helper will affect this figure.

    if nargin < 5
        scenKeep = [];
    end
    if nargin < 6 || isempty(EF_year)
        error('EF_year must be provided.');
    end

      KPI.Scenario = string(KPI.Scenario);


    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end

    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m, :);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    % Ensure Nuclear color exists (fallback)
    if ~isfield(colorsBase, 'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    % KPI capacity columns required for EOL provision
    reqCols = ["Cap2050_Solar","Cap2050_Battery"];
    for r = 1:numel(reqCols)
        if ~ismember(reqCols(r), string(K.Properties.VariableNames))
            error('Missing KPI column required for externalities: %s', reqCols(r));
        end
    end

    keptRE = zeros(0,1);

    % Store:
    % [NucOPEX NucCAPEX] + Gas(2) + Batt(2) + Solar(2) + Coal(2) + ExtTotal
    keptCost = zeros(0,11);

    hasNuclearAny = false;

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');

        if ~isfile(resFile)
            warning('Missing results_heavy.mat for %s, skipping.', scName);
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;

        if ~isfield(RES,'BaseYear') || ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource')
            continue;
        end

        y2050Idx = 2050 - RES.BaseYear + 1;
        if y2050Idx < 1 || y2050Idx > size(RES.opCostYearBySource,2)
            continue;
        end
        nYears = size(RES.opCostYearBySource,2);

        nRowsOp = size(RES.opCostYearBySource,1);
        nRowsBu = size(RES.buildCostYearBySource,1);

        % Source order: 1 Nuclear | 2 Solar | 3 Gas | 4 Coal | 5 Battery
        opex_nuc_2050 = 0;
        capex_nuc_avg = 0;

        if nRowsOp >= 1 && nRowsBu >= 1
            if isfinite(RES.opCostYearBySource(1, y2050Idx))
                opex_nuc_2050 = RES.opCostYearBySource(1, y2050Idx);
                hasNuclearAny = true;
            end
            vB = RES.buildCostYearBySource(1, :);
            if ~isempty(vB) && any(isfinite(vB))
                capex_nuc_avg = sum(vB(isfinite(vB))) / nYears;
                hasNuclearAny = true;
            end
        end

        % Defensive indexing for other sources
        if nRowsOp < 5 || nRowsBu < 5
            continue;
        end

        opex_solar_2050 = RES.opCostYearBySource(2, y2050Idx);
        opex_gas_2050   = RES.opCostYearBySource(3, y2050Idx);
        opex_coal_2050  = RES.opCostYearBySource(4, y2050Idx);
        opex_batt_2050  = RES.opCostYearBySource(5, y2050Idx);

        capex_solar_avg = sum(RES.buildCostYearBySource(2, :)) / nYears;
        capex_gas_avg   = sum(RES.buildCostYearBySource(3, :)) / nYears;
        capex_coal_avg  = sum(RES.buildCostYearBySource(4, :)) / nYears;
        capex_batt_avg  = sum(RES.buildCostYearBySource(5, :)) / nYears;

        % --- Externalities in 2050 (NIS/year) via shared helper ---
        capSolar2050_MW = K.Cap2050_Solar(s);
        capBatt2050_MW  = K.Cap2050_Battery(s);

        if ~isfinite(capSolar2050_MW), capSolar2050_MW = 0; end
        if ~isfinite(capBatt2050_MW),  capBatt2050_MW  = 0; end

        ext2050_NIS = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);
        if ~isfinite(ext2050_NIS), ext2050_NIS = 0; end

        rowBillion = [ ...
            opex_nuc_2050,   capex_nuc_avg, ...
            opex_gas_2050,   capex_gas_avg, ...
            opex_batt_2050,  capex_batt_avg, ...
            opex_solar_2050, capex_solar_avg, ...
            opex_coal_2050,  capex_coal_avg, ...
            ext2050_NIS ...
        ] / 1e9;

        keptRE(end+1,1) = re_sorted(s); %#ok<AGROW>
        keptCost(end+1,:) = rowBillion; %#ok<AGROW>
    end

    if isempty(keptRE)
        fig = figure('Color','w');
        warning('No scenarios available for cost figure (all skipped).');
        return;
    end

    % If Nuclear never appears, drop it to keep previous behavior/order
    if ~hasNuclearAny
        keptCost = keptCost(:, 3:end); % remove [NucOPEX NucCAPEX]
    end

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax  = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    hb = bar(ax, 1:size(keptCost,1), keptCost, 'stacked', 'EdgeColor', 'none');

    % Base palettes (OPEX: base, CAPEX: lighter)
    nucOpex   = colorsBase.Nuclear;  nucCapex  = 0.65*colorsBase.Nuclear + 0.35*[1 1 1];
    gasOpex   = colorsBase.Gas;      gasCapex  = 0.65*colorsBase.Gas     + 0.35*[1 1 1];
    battOpex  = colorsBase.Batt;     battCapex = 0.65*colorsBase.Batt    + 0.35*[1 1 1];
    solarOpex = colorsBase.Solar;    solarCapex= 0.65*colorsBase.Solar   + 0.35*[1 1 1];
    coalOpex  = colorsBase.Coal;     coalCapex = 0.65*colorsBase.Coal    + 0.35*[1 1 1];

    extColor = [0.35 0.35 0.35];

    if ~hasNuclearAny
        palette = [ ...
            gasOpex; gasCapex; ...
            battOpex; battCapex; ...
            solarOpex; solarCapex; ...
            coalOpex; coalCapex; ...
            extColor ...
        ];
        legText = { ...
            'Gas (OPEX)', 'Gas (CAPEX)', ...
            'Battery (OPEX)', 'Battery (CAPEX)', ...
            'Solar (OPEX)', 'Solar (CAPEX)', ...
            'Coal (OPEX)', 'Coal (CAPEX)', ...
            'Externalities (Climate + EOL)' ...
        };
    else
        palette = [ ...
            nucOpex; nucCapex; ...
            gasOpex; gasCapex; ...
            battOpex; battCapex; ...
            solarOpex; solarCapex; ...
            coalOpex; coalCapex; ...
            extColor ...
        ];
        legText = { ...
            'Nuclear (OPEX)', 'Nuclear (CAPEX)', ...
            'Gas (OPEX)', 'Gas (CAPEX)', ...
            'Battery (OPEX)', 'Battery (CAPEX)', ...
            'Solar (OPEX)', 'Solar (CAPEX)', ...
            'Coal (OPEX)', 'Coal (CAPEX)', ...
            'Externalities (Climate + EOL)' ...
        };
    end

    for k = 1:numel(hb)
        hb(k).FaceColor = palette(k,:);
    end

    ylabel(ax, 'Annual cost in 2050 [billion ₪]', 'FontWeight','bold');
    xlabel(ax, 'Renewables blocks (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'Annual system cost in 2050 - OPEX + CAPEX + externalities (ex post)');

    legend(ax, legText, 'Location','northoutside', 'Orientation','horizontal');

    ax.XGrid = 'off';
    ax.YGrid = 'on';

    if nargin < 5 || isempty(scenKeep)
        applyReBlockTicks(ax, keptRE, 0.1);
    else
        applyReAllScenarioTicks(ax, keptRE);
    end
end

function fig = PLOT_CAPACITY2050_STACK_BY_SOURCE_ALL(KPI, colorsBase, reTargets, scenKeep)
% Installed capacity in 2050 by source (stacked), GW
% Nuclear included in main stack (bottom) if available in KPI/columns.
% Battery shown as a separate adjacent bar (same scale).

    if nargin < 4
        scenKeep = [];
    end

    if iscell(KPI.Scenario) || ischar(KPI.Scenario)
        KPI.Scenario = string(KPI.Scenario);
    end

    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Ensure Nuclear color exists (fallback)
    if ~isfield(colorsBase, 'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    % Required KPI columns (battery separate, others in main stack)
    reqBase = ["Cap2050_Gas","Cap2050_Battery","Cap2050_Solar","Cap2050_Coal"];
    for r = 1:numel(reqBase)
        if ~ismember(reqBase(r), string(K.Properties.VariableNames))
            error('Missing KPI column: %s', reqBase(r));
        end
    end

    hasNuclearCol = ismember("Cap2050_Nuclear", string(K.Properties.VariableNames));

    % ---------- Data (convert MW -> GW) ----------
    if hasNuclearCol
        Y_stack = [ ...
            K.Cap2050_Nuclear, ...
            K.Cap2050_Gas, ...
            K.Cap2050_Solar, ...
            K.Cap2050_Coal ...
        ] / 1000;   % MW -> GW

        stackLabels = {'Nuclear','Gas','Solar','Coal'};
        stackColors = {colorsBase.Nuclear, colorsBase.Gas, colorsBase.Solar, colorsBase.Coal};
    else
        Y_stack = [ ...
            K.Cap2050_Gas, ...
            K.Cap2050_Solar, ...
            K.Cap2050_Coal ...
        ] / 1000;   % MW -> GW

        stackLabels = {'Gas','Solar','Coal'};
        stackColors = {colorsBase.Gas, colorsBase.Solar, colorsBase.Coal};
    end

    Y_batt = K.Cap2050_Battery(:) / 1000;   % MW -> GW

    nScen = size(Y_stack,1);
    xMain = 1:nScen;

    dx    = 0.32;    % horizontal offset for battery
    wMain = 0.75;
    wBatt = 0.28;

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    % ---------- Main stacked bars ----------
    hb = bar(ax, xMain, Y_stack, 'stacked', ...
        'EdgeColor','none', 'BarWidth', wMain);

    for k = 1:numel(hb)
        hb(k).FaceColor = stackColors{k};
    end

    % ---------- Battery as adjacent bar ----------
    bar(ax, xMain + dx, Y_batt, ...
        'FaceColor', colorsBase.Batt, ...
        'EdgeColor','none', ...
        'BarWidth', wBatt);

    % ---------- Labels ----------
    ylabel(ax, 'Installed capacity in 2050 [GW]', 'FontWeight','bold');
    xlabel(ax, 'Renewables blocks (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'Installed capacity in 2050 by source (GW), Battery 4H Model (charge from solar)');

    legend(ax, [stackLabels, {'Battery (4H Model, charge from solar)'}], ...
        'Location','northoutside', 'Orientation','horizontal');

    % ---------- Y ticks and grid (25 GW) ----------
    step = 25;   % GW
    yl = ylim(ax);
    y0 = step * floor(yl(1)/step);
    y1 = step * ceil(yl(2)/step);
    yticks(ax, y0:step:y1);

    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%.0f');

    ax.YGrid = 'on';
    ax.XGrid = 'on';

    % ---------- X limits ----------
    xlim(ax, [0.5, nScen + 0.8]);

    % ---------- X ticks ----------
    if nargin < 4 || isempty(scenKeep)
        applyReBlockTicks(ax, re_sorted, 0.1);
    else
        applyReAllScenarioTicks(ax, re_sorted);
    end
end




function MESH3D_RESULTS(KPI)
% 3D mesh: Cost vs Land vs % Renewables (2050)
% Also exports a clean table of the numeric points used in the mesh.

if iscell(KPI.Scenario) || ischar(KPI.Scenario)
    KPI.Scenario = string(KPI.Scenario);
end

if any(KPI.Scenario == "S101_Special")
    KPI = KPI(KPI.Scenario ~= "S101_Special", :);
end

x = KPI.MaxCost(:) / 1e11;
y = KPI.MaxAreaSolar(:);
z = KPI.RenewablesPct2050(:);

m = isfinite(x) & isfinite(y) & isfinite(z);
x = x(m); y = y(m); z = z(m);

scen = strings(numel(m),1);
if ismember('Scenario', KPI.Properties.VariableNames)
    scen = KPI.Scenario(:);
else
    scen = repmat("", height(KPI), 1);
end
scen = scen(m);

if numel(z) < 3
    warning('Not enough valid scenarios to build triangulation.');
    return;
end

DT  = delaunayTriangulation(x, y);
tri = DT.ConnectivityList;

ax = gca;
hold(ax,'on'); grid(ax,'on'); box(ax,'on');

trisurf(tri, x, y, z, z, ...
    'FaceColor','none', ...
    'EdgeColor','interp', ...
    'LineWidth',0.8);

xlabel(ax, 'MaxCost [₪×10^{11}]', 'FontWeight','bold');
ylabel(ax, 'MaxAreaSolar',        'FontWeight','bold');
zlabel(ax, '% Renewables (2050)', 'FontWeight','bold');
title(ax, 'Mesh: Cost vs Land vs %RE (2050)');

colormap(ax, parula);
cb = colorbar(ax);
cb.Label.String = '% Renewables (2050)';
zticks(ax, 0:10:100);
view(ax, [-35, 20]);
axis(ax,'tight');
ax.MinorGridAlpha = 0.2;
ax.GridAlpha      = 0.25;

% ---------- Build matrix representation of the mesh ----------

xVals = unique(x);   % MaxCost (₪×1e11)
yVals = unique(y);   % MaxAreaSolar
xVals = xVals(:)';   % force row
yVals = yVals(:);    % force column


nx = numel(xVals);
ny = numel(yVals);

Zmat = nan(ny, nx);  % Rows: Area, Columns: Cost

for k = 1:numel(z)
    ix = find(xVals == x(k), 1);
    iy = find(yVals == y(k), 1);
    Zmat(iy, ix) = z(k);
end

% ---------- Save MAT ----------
MESH_MATRIX.MaxCost_1e11NIS = xVals;
MESH_MATRIX.MaxAreaSolar   = yVals;
MESH_MATRIX.RenewablesPct  = Zmat;

outMat = fullfile(pwd, 'MESH3D_RESULTS_matrix.mat');
save(outMat, 'MESH_MATRIX');

% ---------- Save CSV as a true matrix ----------
outCsv = fullfile(pwd, 'MESH3D_RESULTS_matrix.csv');

xHdr = "Cost_" + string(xVals);            % 1 x nx
csvTbl = array2table(Zmat, 'VariableNames', cellstr(xHdr));
csvTbl = addvars(csvTbl, yVals, 'Before', 1, 'NewVariableNames', 'MaxAreaSolar');

try
    writetable(csvTbl, outCsv);
catch ME
    warning('MESH3D_RESULTS:WriteCSV', 'Failed to write matrix CSV: %s', char(ME.message));
end



end

function UI_PLOT_HOURLY_FROM_RESULTS_HEAVY(Demand, startYr, yearLen, useUI)
% UI_PLOT_HOURLY_FROM_RESULTS_HEAVY
% Hourly plot from a chosen results_heavy.mat.
% Uses Demand passed from the master script.
%
% Update:
% - Supports optional Nuclear generation (source order: [Nuclear, Solar, Gas, Coal, Battery]).
% - Nuclear is stacked FIRST (bottom), and all other sources keep the same stacking order as before.
% - Keeps full time range (does NOT truncate to one year). The input yearLen is ignored (kept for API compatibility).
% - Allows plotting either into uifigure (useUI=true) or standard figure (useUI=false).
% - Prints renewables share for years 2023, 2030, 2050 to Command Window for the selected scenario.

if exist('hours','var')
    clear hours
end

% Defaults
if nargin < 2 || isempty(startYr)
    startYr = 2023;
end
if nargin < 3 %#ok<NASGU>
    yearLen = []; %#ok<NASGU>
end
if nargin < 4 || isempty(useUI)
    useUI = true;
end

[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'; '*.*','All files (*.*)'}, ...
    'Select results_heavy.mat file');
if isequal(fn,0)
    warning('No results_heavy selected. Skipping hourly plot.');
    return;
end

fullMat = fullfile(fp, fn);
S = load(fullMat, 'RES');
if ~isfield(S,'RES')
    error('Selected MAT does not contain RES struct.');
end
RES = S.RES;

if ~isfield(RES,'U') || isempty(RES.U)
    error('RES.U is missing or empty in the selected results_heavy.mat.');
end

U = RES.U;

% Robust field access
ChB  = zeros(size(U,2),1);
Dump = zeros(size(U,2),1);

if isfield(RES,'ChB') && ~isempty(RES.ChB),   ChB  = RES.ChB(:);  end
if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end

T = size(U,2);
hIdx = (0:T-1)';

% Make datetime axis (explicit hourly duration)
dt0 = datetime(startYr,1,1,0,0,0);
dt  = dt0 + seconds(3600 * hIdx);

Demand = Demand(:);

% Align lengths safely
Tmin = T;
if numel(Demand) < Tmin, Tmin = numel(Demand); end
if numel(ChB)   < Tmin, Tmin = numel(ChB);   end
if numel(Dump)  < Tmin, Tmin = numel(Dump);  end

if Tmin < T
    warning('One or more inputs shorter than U. Using min length %d.', Tmin);
    T = Tmin;
    U     = U(:,1:T);
    ChB   = ChB(1:T);
    Dump  = Dump(1:T);
    dt    = dt(1:T);
end

DemandC = Demand(1:T);

% Project source order: [Nuclear, Solar, Gas, Coal, Battery]
nSrc = size(U,1);

U_nuc  = zeros(T,1);
U_sol  = zeros(T,1);
U_gas  = zeros(T,1);
U_coal = zeros(T,1);
U_batt = zeros(T,1);

if nSrc >= 1, U_nuc  = U(1,:)'; end
if nSrc >= 2, U_sol  = U(2,:)'; end
if nSrc >= 3, U_gas  = U(3,:)'; end
if nSrc >= 4, U_coal = U(4,:)'; end
if nSrc >= 5, U_batt = U(5,:)'; end

hasNuclear = (nSrc >= 1);

% Build stacked matrix with Nuclear first (if present), then keep legacy order
if hasNuclear
    Y_all = [U_nuc, U_gas, U_coal, U_sol, U_batt, ChB(:), Dump(:)];
    legNames = {'Nuclear','Gas','Coal','Solar to grid','Battery from Solar','Solar to Battery','Solar Wasted','Demand'};
    cmap = [ ...
        0.25 0.35 0.60 ;   % Nuclear
        0.75 0.25 0.25 ;   % Gas
        0.55 0.35 0.65 ;   % Coal
        0.90 0.75 0.25 ;   % Solar
        0.30 0.65 0.40 ;   % Battery
        0.40 0.80 0.85 ;   % Solar->Battery
        0.60 0.60 0.60 ];  % Dump
else
    Y_all = [U_gas, U_coal, U_sol, U_batt, ChB(:), Dump(:)];
    legNames = {'Gas','Coal','Solar to grid','Battery from Solar','Solar to Battery','Solar Wasted','Demand'};
    cmap = [ ...
        0.75 0.25 0.25 ;   % Gas
        0.55 0.35 0.65 ;   % Coal
        0.90 0.75 0.25 ;   % Solar
        0.30 0.65 0.40 ;   % Battery
        0.40 0.80 0.85 ;   % Solar->Battery
        0.60 0.60 0.60 ];  % Dump
end

% Print renewables share (Nuclear + Solar + Battery) for selected years
yearsToReport = [2023, 2030, 2050];

fprintf('\n============================================================\n');
fprintf('Selected results file: %s\n', fullMat);
fprintf('Renewables share (Nuclear + Solar + Battery) by year:\n');

for yy = yearsToReport
    yMask = (year(dt) == yy);

    if ~any(yMask)
        fprintf('  %d: N/A (year not present in time series)\n', yy);
        continue;
    end

    sumNuc  = 0; if nSrc >= 1, sumNuc  = sum(U_nuc(yMask));  end
    sumSol  = 0; if nSrc >= 2, sumSol  = sum(U_sol(yMask));  end
    sumGas  = 0; if nSrc >= 3, sumGas  = sum(U_gas(yMask));  end
    sumCoal = 0; if nSrc >= 4, sumCoal = sum(U_coal(yMask)); end
    sumBat  = 0; if nSrc >= 5, sumBat  = sum(U_batt(yMask)); end

    totalDelivered = sumNuc + sumSol + sumGas + sumCoal + sumBat;
    renewDelivered = sumNuc + sumSol + sumBat;  % Nuclear included as renewable

    if totalDelivered > 0
        rePct = 100 * renewDelivered / totalDelivered;
        fprintf('  %d: %.2f%%\n', yy, rePct);
    else
        fprintf('  %d: N/A (total delivered is zero)\n', yy);
    end
end

fprintf('============================================================\n\n');


% Create figure either UI or standard
if useUI
    analysisFig = uifigure('Name','Hourly Analysis', 'Position',[200 100 1200 720]);
    tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);
    tabHourly = uitab(tg,'Title','Hourly mix');
    ax = uiaxes(tabHourly,'Position',[60 80 1100 580]);

    hBar = bar(ax, dt, Y_all, 'stacked', 'EdgeColor','none', 'BarWidth', 1);
    hold(ax,'on');
    for k = 1:numel(hBar)
        hBar(k).FaceColor = cmap(k,:);
    end

    plot(ax, dt, DemandC, 'k-', 'LineWidth', 0.8);

    xlabel(ax,'Date');
    ylabel(ax,'Energy [MWh]');
    title(ax,'Generation mix - hourly');
    grid(ax,'on'); box(ax,'on');

    legend(ax, legNames, 'Location','northoutside','Orientation','horizontal');
    ax.XAxis.TickLabelRotation = 0;
    ax.XAxis.TickLabelFormat = 'dd/MM/yyyy';

else
    fig = figure('Color','w','Position',[200 100 1200 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    hBar = bar(ax, dt, Y_all, 'stacked', 'EdgeColor','none', 'BarWidth', 1);
    for k = 1:numel(hBar)
        hBar(k).FaceColor = cmap(k,:);
    end

    plot(ax, dt, DemandC, 'r-', 'LineWidth', 0.1);;   

    xlabel(ax,'Date');
    ylabel(ax,'Energy [MWh]');
    title(ax,'Generation mix - hourly');
    legend(ax, legNames, 'Location','northoutside','Orientation','horizontal');

    ax.XAxis.TickLabelRotation = 0;
    ax.XAxis.TickLabelFormat = 'dd/MM/yyyy';
end

end



%{
function UI_PLOT_HOURLY_FROM_RESULTS_HEAVY(Demand, startYr, yearLen)
% UI plot (hourly) from a chosen results_heavy.mat
% Uses Demand passed from the master script.
%
% Update:
% - Supports optional Nuclear generation (source order: [Nuclear, Solar, Gas, Coal, Battery]).
% - Nuclear is stacked FIRST (bottom), and all other sources keep the same stacking order as before.
% - Keeps full time range (does NOT truncate to one year). The input yearLen is ignored (kept for API compatibility).

if exist('hours','var')
    clear hours
end

% Keep signature compatibility, but do not truncate by yearLen
if nargin < 2 || isempty(startYr)
    startYr = 2023;
end
% yearLen is intentionally unused (legacy argument)
if nargin < 3 %#ok<NASGU>
    yearLen = []; %#ok<NASGU>
end

[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'; '*.*','All files (*.*)'}, ...
    'Select results_heavy.mat file');
if isequal(fn,0)
    warning('No results_heavy selected. Skipping UI hourly plot.');
    return;
end

fullMat = fullfile(fp, fn);
S = load(fullMat, 'RES');
if ~isfield(S,'RES')
    error('Selected MAT does not contain RES struct.');
end
RES = S.RES;

U    = RES.U;

% Robust field access (some runs may miss these fields)
ChB  = zeros(size(U,2),1);
Dump = zeros(size(U,2),1);
E    = zeros(size(U,2),1); %#ok<NASGU> % Loaded for compatibility; not used in the legacy stacking here.

if isfield(RES,'ChB') && ~isempty(RES.ChB),   ChB  = RES.ChB(:);  end
if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end
if isfield(RES,'E') && ~isempty(RES.E),       E    = RES.E(:);    end

T = size(U,2);
hIdx = (0:T-1)';

% Make datetime axis (explicit hourly duration)
dt0 = datetime(startYr,1,1,0,0,0);
dt  = dt0 + seconds(3600 * hIdx);

Demand = Demand(:);

% Align lengths safely
Tmin = T;
if numel(Demand) < Tmin
    Tmin = numel(Demand);
end
if numel(ChB) < Tmin
    Tmin = numel(ChB);
end
if numel(Dump) < Tmin
    Tmin = numel(Dump);
end
% E is not used in stacking here, but keep it aligned to avoid surprises
if numel(E) < Tmin
    Tmin = numel(E);
end

if Tmin < T
    warning('One or more inputs shorter than U. Using min length %d.', Tmin);
    T = Tmin;
    U    = U(:,1:T);
    ChB  = ChB(1:T);
    Dump = Dump(1:T);
    E    = E(1:T);
    dt   = dt(1:T);
end

DemandC = Demand(1:T);

% Project source order: [Nuclear, Solar, Gas, Coal, Battery]
% Legacy stacking order (kept): Gas, Coal, Solar-to-grid, Battery, Solar->Battery, Dump
nSrc = size(U,1);
hasNuclear = (nSrc >= 1);

U_nuc  = zeros(T,1);
U_sol  = zeros(T,1);
U_gas  = zeros(T,1);
U_coal = zeros(T,1);
U_batt = zeros(T,1);

if nSrc >= 1, U_nuc  = U(1,:)'; end
if nSrc >= 2, U_sol  = U(2,:)'; end
if nSrc >= 3, U_gas  = U(3,:)'; end
if nSrc >= 4, U_coal = U(4,:)'; end
if nSrc >= 5, U_batt = U(5,:)'; end

% Build stacked matrix with Nuclear first (if present), then keep legacy order
if hasNuclear
    Y_all = [U_nuc, U_gas, U_coal, U_sol, U_batt, ChB(:), Dump(:)];
    legNames = {'Nuclear','Gas','Coal','Solar to grid','Battery from Solar','Solar to Battery','Solar Wasted','Demand'};
    cmap = [ ...
        0.25 0.35 0.60 ;   % Nuclear (soft navy / steel-blue)
        0.75 0.25 0.25 ;   % Gas
        0.55 0.35 0.65 ;   % Coal (purple)
        0.90 0.75 0.25 ;   % Solar
        0.30 0.65 0.40 ;   % Battery
        0.40 0.80 0.85 ;   % Solar->Battery
        0.60 0.60 0.60 ];  % Dump (gray)
else
    Y_all = [U_gas, U_coal, U_sol, U_batt, ChB(:), Dump(:)];
    legNames = {'Gas','Coal','Solar to grid','Battery from Solar','Solar to Battery','Solar Wasted','Demand'};
    cmap = [ ...
        0.75 0.25 0.25 ;   % Gas
        0.55 0.35 0.65 ;   % Coal (purple)
        0.90 0.75 0.25 ;   % Solar
        0.30 0.65 0.40 ;   % Battery
        0.40 0.80 0.85 ;   % Solar->Battery
        0.60 0.60 0.60 ];  % Dump (gray)
end

analysisFig = uifigure('Name','Hourly Analysis', 'Position',[200 100 1200 720]);
tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);

tabHourly = uitab(tg,'Title','Hourly mix');
ax = uiaxes(tabHourly,'Position',[60 80 1100 580]);

hBar = bar(ax, dt, Y_all, 'stacked', 'EdgeColor','none', 'BarWidth', 1);
hold(ax,'on');
for k = 1:numel(hBar)
    hBar(k).FaceColor = cmap(k,:);
end

% Demand line (thin black)
plot(ax, dt, DemandC, 'k-', 'LineWidth', 0.8);

xlabel(ax,'Date');
ylabel(ax,'Energy [MWh]');
title(ax,'Generation mix - hourly');
grid(ax,'on'); box(ax,'on');

legend(ax, legNames, 'Location','northoutside','Orientation','horizontal');

ax.XAxis.TickLabelRotation = 0;
ax.XAxis.TickLabelFormat = 'dd/MM/yyyy';

end
%}
function c = localColor(name)
% Fallback palette (replace with your palette later if you decide to pass colorsBase into this function)
    switch lower(name)
        case 'gas'
            c = [0.85 0.33 0.10];
        case 'batt'
            c = [0.47 0.67 0.19];
        case 'solar'
            c = [0.93 0.69 0.13];
        case 'coal'
            c = [0.20 0.20 0.20];
        case 'dump'
            c = [0.35 0.35 0.35];
        otherwise
            c = [0.5 0.5 0.5];
    end
end

function c = colorsafe(name)
% Safe fallback palette if colorsBase is not available inside this UI function.
% If you already have colorsBase in scope, replace this function usage accordingly.

    switch lower(name)
        case 'gas'
            c = [0.85 0.33 0.10];
        case 'batt'
            c = [0.47 0.67 0.19];
        case 'solar'
            c = [0.93 0.69 0.13];
        case 'coal'
            c = [0.20 0.20 0.20];
        case 'dump'
            c = [0.35 0.35 0.35];
        otherwise
            c = [0.5 0.5 0.5];
    end
end

function [fig, scenKeepB] = PLOT_LCOE2050_SELECTED_SCENARIOS(KPI, scenRoot, binSizePct, EF_year)
% PLOT_LCOE2050_SELECTED_SCENARIOS
% Select representative scenarios across %RE in 2050, using piecewise %RE bins,
% and plot their LCOE in 2050.
%
% Selection logic:
% - Below 90% RE: keep up to 2 minimum-LCOE scenarios per bin, enforcing RE separation >= 0.1%.
% - At/above 90% RE: use 2% bins (90-92, 92-94, 94-96, 96-98, 98-100) and keep only 1 scenario per bin.
%
% LCOE includes NEW externalities only (ex post):
% - Climate externality in 2050: Emissions2050[tCO2e] * SCC[₪/tCO2e]
% - End-of-life (EOL) annual provision in 2050:
%     Cap2050_Solar[MW] * EOL_Solar[₪/MW] / LifeSolar[yr] +
%     Cap2050_Battery[MW] * EOL_Batt[₪/MW] / LifeBatt[yr]
%
% binSizePct kept for backward compatibility; not used.

    %#ok<*AGROW>
    if nargin < 3
        binSizePct = [];
    end
    if nargin < 4 || isempty(EF_year)
        error('EF_year must be provided.');
    end
    if isempty(binSizePct)
        binSizePct = NaN; %#ok<NASGU>
    end

    KPI.Scenario = string(KPI.Scenario);

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m, :);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    % Require capacities for EOL provision
    vn = string(K.Properties.VariableNames);
    if ~ismember("Cap2050_Solar", vn) || ~ismember("Cap2050_Battery", vn)
        error('KPI must contain Cap2050_Solar and Cap2050_Battery for externalities-based LCOE.');
    end

    % Minimum RE separation within a bin (percentage points) for the "up to 2" rule
    RE_MIN_GAP_PCT = 0.1;

    sc_sorted = string(K.Scenario);
    n = height(K);

    y2050 = nan(n,1);
    yBase = nan(n,1);
    yAll  = nan(n,1);

    % Compute LCOE series per scenario (Base, AllYearsAvg, 2050)
    for i = 1:n
        scName  = sc_sorted(i);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;

        if ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource') || ...
           ~isfield(RES,'elecYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        nYears = size(RES.opCostYearBySource, 2);

        % Year indices
        yBaseIdx = 1;
        y2050Idx = 2050 - RES.BaseYear + 1;

        if yBaseIdx < 1 || yBaseIdx > nYears || yBaseIdx > numel(RES.elecYear)
            continue;
        end
        if y2050Idx < 1 || y2050Idx > nYears || y2050Idx > numel(RES.elecYear)
            continue;
        end

        % Annualized CAPEX (NIS/year)
        capexAvg = sum(RES.buildCostYearBySource(:), 'all') / nYears;

        % NEW externalities in 2050 (NIS/year)
        capSolar2050_MW = K.Cap2050_Solar(i);
        capBatt2050_MW  = K.Cap2050_Battery(i);

        ext2050 = local_externalities_2050_NIS( ...
            RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);

        if ~isfinite(ext2050)
            ext2050 = 0;
        end

        % Base year LCOE (include ext2050 for consistency)
        opexBase = sum(RES.opCostYearBySource(:, yBaseIdx), 1);
        elecBase_MWh = RES.elecYear(yBaseIdx);
        if isfinite(elecBase_MWh) && elecBase_MWh > 0
            yBase(i) = (opexBase + capexAvg + ext2050) / (elecBase_MWh * 1000);
        end

        % All-years average LCOE (include ext2050 for consistency)
        opexAll = sum(RES.opCostYearBySource, 1);     % 1 x nYears
        elecAll_MWh = RES.elecYear(:)';               % 1 x nYears
        ok = isfinite(opexAll) & isfinite(elecAll_MWh) & (elecAll_MWh > 0);
        if any(ok)
            yAll(i) = mean( (opexAll(ok) + capexAvg + ext2050) ./ (elecAll_MWh(ok) * 1000) );
        end

        % 2050 LCOE (selection metric)
        opex2050_i = sum(RES.opCostYearBySource(:, y2050Idx), 1);
        elec2050_MWh = RES.elecYear(y2050Idx);
        if isfinite(elec2050_MWh) && elec2050_MWh > 0
            y2050(i) = (opex2050_i + capexAvg + ext2050) / (elec2050_MWh * 1000);
        end
    end

    % Keep valid values for selection
    ok = isfinite(re_sorted) & isfinite(y2050);
    re_use    = re_sorted(ok);
    y2050_use = y2050(ok);
    yBase_use = yBase(ok);
    yAll_use  = yAll(ok);
    sc_use    = sc_sorted(ok);

    if isempty(y2050_use)
        fig = figure('Color','w');
        title('No valid scenarios for LCOE selection');
        scenKeepB = strings(0,1);
        return;
    end

    % Assign each scenario to a piecewise bin key (>=90 uses 2% bins)
    binKey    = strings(size(re_use));
    isHi90Bin = false(size(re_use));
    for i = 1:numel(re_use)
        [binKey(i), isHi90Bin(i)] = localPiecewiseBinKey_Selected(re_use(i));
    end

    % Group by binKey and select scenarios per bin according to rules
    [keysUnique, ~, g] = unique(binKey, 'stable');
    keepMask = false(size(y2050_use));

    for k = 1:numel(keysUnique)
        idxk = find(g == k);
        if isempty(idxk)
            continue;
        end

        % Sort candidates in this bin by LCOE (ascending)
        [~, ord] = sort(y2050_use(idxk), 'ascend');
        cand = idxk(ord);

        % Decide selection rule for this bin:
        % If this bin is a >=90% bin, keep only 1.
        isBinHi90 = any(isHi90Bin(idxk));

        take1 = cand(1);
        keepMask(take1) = true;

        if ~isBinHi90
            % Below 90%: keep up to 2, enforcing RE separation >= RE_MIN_GAP_PCT
            re1 = re_use(take1);
            take2 = [];
            for jj = 2:numel(cand)
                re2 = re_use(cand(jj));
                if isfinite(re2) && isfinite(re1) && abs(re2 - re1) >= RE_MIN_GAP_PCT
                    take2 = cand(jj);
                    break;
                end
            end
            if ~isempty(take2)
                keepMask(take2) = true;
            end
        end
    end

    scenKeepB = sc_use(keepMask);

    % Sort kept scenarios by RE for plotting
    re_keep      = re_use(keepMask);
    y_keep       = y2050_use(keepMask);
    yBase_keep   = yBase_use(keepMask);
    yAll_keep    = yAll_use(keepMask);

    [re_keep, ord2] = sort(re_keep, 'ascend');
    y_keep     = y_keep(ord2);
    yBase_keep = yBase_keep(ord2);
    yAll_keep  = yAll_keep(ord2);
    scenKeepB  = scenKeepB(ord2);

    % Plot (2050 only) - points only
    fig = figure('Color','w','Position',[220 160 1200 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    plot(ax, 1:numel(y_keep), y_keep, 'o', 'MarkerSize', 6, ...
        'MarkerFaceColor', [0.35 0.35 0.35], 'MarkerEdgeColor', [0.35 0.35 0.35]);

    ylabel(ax, 'LCOE 2050 [NIS/kWh]', 'FontWeight','bold', 'FontSize', 16);
    xlabel(ax, 'Selected scenarios (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'LCOE 2050 [NIS/kWh] - selected scenarios (min per %RE bin)');

    applyReAllScenarioTicks(ax, re_keep);

    % Store extra series for later use (not shown)
    ax.UserData.RE_sorted_used     = re_keep;
    ax.UserData.Scenarios_used     = scenKeepB;
    ax.UserData.LCOE_2050          = y_keep;
    ax.UserData.LCOE_Base          = yBase_keep;
    ax.UserData.LCOE_AllYearsAvg   = yAll_keep;
end

function [key, isHi90Bin] = localPiecewiseBinKey_Selected(rePct)
% Piecewise binning used for selecting representative scenarios.
% - <=10%: 2.5% bins
% - 10-70%: 10% bins
% - 70-90%: 5% bins
% - >=90%: 2% bins (90-92, 92-94, 94-96, 96-98, 98-100)

    if ~isfinite(rePct)
        key = "NA";
        isHi90Bin = false;
        return;
    end

    rePct = max(0, min(100, rePct));

    if rePct <= 10
        w = 2.5;
        b = floor(rePct / w);
        b = min(b, 3);
        lo = b*w;
        hi = (b+1)*w;
        if b == 3
            hi = 10;
        end
        isHi90Bin = false;

    elseif rePct < 70
        w = 10;
        b = floor((rePct - 10) / w);
        b = min(max(b,0), 5);
        lo = 10 + b*w;
        hi = lo + w;
        isHi90Bin = false;

    elseif rePct < 90
        w = 5;
        b = floor((rePct - 70) / w);
        b = min(max(b,0), 3);
        lo = 70 + b*w;
        hi = lo + w;
        isHi90Bin = false;

    else
        % 2% bins from 90 to 100
        w = 2;
        b = floor((rePct - 90) / w);
        b = min(max(b,0), 4);
        lo = 90 + b*w;
        hi = lo + w;
        if b == 4
            hi = 100;
        end
        isHi90Bin = true;
    end

    key = sprintf("RE_%05.1f_%05.1f", lo, hi);
end

%{
function [fig, scenKeepB] = PLOT_LCOE2050_MIN_PER_REBIN(KPI, scenRoot, binSizePct, EF_year)
% Select representative scenarios by piecewise %RE bins, keeping up to 2 minimum-LCOE
% scenarios per bin (based on LCOE_2050), enforcing RE separation >= 0.1%.
%
% LCOE includes NEW externalities only (no fixed penalty):
% - Climate externality in 2050: Emissions2050[tCO2e] * SCC[₪/tCO2e]
% - EOL annual provision in 2050:
%     Cap2050_Solar[MW] * EOL_Solar[₪/MW] / LifeSolar[yr] +
%     Cap2050_Battery[MW] * EOL_Batt[₪/MW] / LifeBatt[yr]
%
% binSizePct kept for backward compatibility; not used.

    %#ok<*AGROW>
    if nargin < 3
        binSizePct = [];
    end
    if nargin < 4 || isempty(EF_year)
        error('EF_year must be provided.');
    end
    if isempty(binSizePct)
        binSizePct = NaN; %#ok<NASGU>
    end

    KPI.Scenario = string(KPI.Scenario);


    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m, :);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    % Require capacities for EOL provision
    vn = string(K.Properties.VariableNames);
    if ~ismember("Cap2050_Solar", vn) || ~ismember("Cap2050_Battery", vn)
        error('KPI must contain Cap2050_Solar and Cap2050_Battery for externalities-based LCOE.');
    end

    % Minimum RE separation within a bin (percentage points)
    RE_MIN_GAP_PCT = 0.1;

    sc_sorted = string(K.Scenario);
    n = height(K);

    y2050 = nan(n,1);
    yBase = nan(n,1);
    yAll  = nan(n,1);

    % Compute LCOE series per scenario (Base, AllYearsAvg, 2050)
    for i = 1:n
        scName  = sc_sorted(i);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES'); continue; end
        RES = S.RES;

        if ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource') || ...
           ~isfield(RES,'elecYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        nYears = size(RES.opCostYearBySource, 2);

        % Year indices
        yBaseIdx = 1;
        y2050Idx = 2050 - RES.BaseYear + 1;

        if yBaseIdx < 1 || yBaseIdx > nYears || yBaseIdx > numel(RES.elecYear)
            continue;
        end
        if y2050Idx < 1 || y2050Idx > nYears || y2050Idx > numel(RES.elecYear)
            continue;
        end

        % Annualized CAPEX (NIS/year)
        capexAvg = sum(RES.buildCostYearBySource(:), 'all') / nYears;

        % NEW externalities in 2050 (NIS/year)
        capSolar2050_MW = K.Cap2050_Solar(i);
        capBatt2050_MW  = K.Cap2050_Battery(i);

        ext2050 = local_externalities_2050_NIS( ...
            RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);

        if ~isfinite(ext2050)
            ext2050 = 0;
        end

        % Base year LCOE (include ext2050 for consistency)
        opexBase = sum(RES.opCostYearBySource(:, yBaseIdx), 1);
        elecBase_MWh = RES.elecYear(yBaseIdx);
        if isfinite(elecBase_MWh) && elecBase_MWh > 0
            yBase(i) = (opexBase + capexAvg + ext2050) / (elecBase_MWh * 1000);
        end

        % All-years average LCOE (include ext2050 for consistency)
        opexAll = sum(RES.opCostYearBySource, 1);     % 1 x nYears
        elecAll_MWh = RES.elecYear(:)';               % 1 x nYears
        ok = isfinite(opexAll) & isfinite(elecAll_MWh) & (elecAll_MWh > 0);
        if any(ok)
            yAll(i) = mean( (opexAll(ok) + capexAvg + ext2050) ./ (elecAll_MWh(ok) * 1000) );
        end

        % 2050 LCOE (selection metric)
        opex2050_i = sum(RES.opCostYearBySource(:, y2050Idx), 1);
        elec2050_MWh = RES.elecYear(y2050Idx);
        if isfinite(elec2050_MWh) && elec2050_MWh > 0
            y2050(i) = (opex2050_i + capexAvg + ext2050) / (elec2050_MWh * 1000);
        end
    end

    % Keep valid values for selection
    ok = isfinite(re_sorted) & isfinite(y2050);
    re_use    = re_sorted(ok);
    y2050_use = y2050(ok);
    yBase_use = yBase(ok);
    yAll_use  = yAll(ok);
    sc_use    = sc_sorted(ok);

    if isempty(y2050_use)
        fig = figure('Color','w');
        title('No valid scenarios for LCOE min-per-bin');
        scenKeepB = strings(0,1);
        return;
    end

    % Assign each scenario to a piecewise bin key
    binKey = strings(size(re_use));
    for i = 1:numel(re_use)
        binKey(i) = localPiecewiseBinKey(re_use(i));
    end

    % Group by binKey and keep up to 2 min-LCOE_2050 scenarios per bin,
    % enforcing RE separation >= RE_MIN_GAP_PCT
    [keysUnique, ~, g] = unique(binKey, 'stable');
    keepMask = false(size(y2050_use));

   for k = 1:numel(keysUnique)
    idxk = find(g == k);
    if isempty(idxk)
        continue;
    end

    [~, ord] = sort(y2050_use(idxk), 'ascend');
    cand = idxk(ord);

    take1 = cand(1);
    re1 = re_use(take1);

    take2 = [];
    for jj = 2:numel(cand)
        re2 = re_use(cand(jj));
        if isfinite(re2) && abs(re2 - re1) >= RE_MIN_GAP_PCT
            take2 = cand(jj);
            break;
        end
    end

    keepMask(take1) = true;
    if ~isempty(take2)
        keepMask(take2) = true;
    end
end


    scenKeepB = sc_use(keepMask);

    % Sort kept scenarios by RE for plotting
    re_keep = re_use(keepMask);
    y_keep  = y2050_use(keepMask);
    yBase_keep = yBase_use(keepMask);
    yAll_keep  = yAll_use(keepMask);

    [re_keep, ord2] = sort(re_keep, 'ascend');
    y_keep = y_keep(ord2);
    yBase_keep = yBase_keep(ord2);
    yAll_keep = yAll_keep(ord2);
    scenKeepB = scenKeepB(ord2);

    % Plot (2050 only) - points only
    fig = figure('Color','w','Position',[220 160 1200 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    plot(ax, 1:numel(y_keep), y_keep, 'o', 'MarkerSize', 6, ...
        'MarkerFaceColor', [0.35 0.35 0.35], 'MarkerEdgeColor', [0.35 0.35 0.35]);

    ylabel(ax, 'LCOE 2050 [NIS/kWh]', 'FontWeight','bold', 'FontSize', 16);
    xlabel(ax, 'Selected scenarios (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'LCOE 2050 [NIS/kWh] (min per RE bin, incl. externalities)');

    applyReAllScenarioTicks(ax, re_keep);

    % Store extra series for later use (not shown)
    ax.UserData.RE_sorted_used = re_keep;
    ax.UserData.Scenarios_used = scenKeepB;
    ax.UserData.LCOE_2050 = y_keep;
    ax.UserData.LCOE_Base = yBase_keep;
    ax.UserData.LCOE_AllYearsAvg = yAll_keep;
end

%}

function key = localPiecewiseBinKey(rePct)
% Return a stable string key representing the piecewise bin that contains rePct.

    if ~isfinite(rePct)
        key = "NA";
        return;
    end

    % Clamp to [0,100] for bin labeling robustness
    rePct = max(0, min(100, rePct));

    if rePct <= 10
        % 2.5% bins: [0-2.49], [2.5-4.99], [5-7.49], [7.5-10]
        w = 2.5;
        b = floor(rePct / w);
        b = min(b, 3); % cap so 10 goes to last bin
        lo = b*w;
        hi = (b+1)*w;
        if b == 3
            hi = 10;
        end
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    elseif rePct < 70
        % 10% bins: [10-19.99], ... [60-69.99]
        w = 10;
        b = floor((rePct - 10) / w);
        b = min(max(b,0), 5);
        lo = 10 + b*w;
        hi = lo + w;
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    elseif rePct < 90
        % 5% bins: [70-74.99], [75-79.99], [80-84.99], [85-89.99]
        w = 5;
        b = floor((rePct - 70) / w);
        b = min(max(b,0), 3);
        lo = 70 + b*w;
        hi = lo + w;
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    else
        % 2.5% bins: [90-92.49], [92.5-94.99], [95-97.49], [97.5-100]
        w = 2.5;
        b = floor((rePct - 90) / w);
        b = min(max(b,0), 3);
        lo = 90 + b*w;
        hi = lo + w;
        if b == 3
            hi = 100;
        end
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);
    end
end
%{
function key = localPiecewiseBinKey(rePct)
% Return a stable string key representing the piecewise bin that contains rePct.
% Boundaries implement the "xx-yy.99" style via half-open intervals, except final caps.

    if ~isfinite(rePct)
        key = "NA";
        return;
    end

    % Clamp to [0,100] for bin labeling robustness
    rePct = max(0, min(100, rePct));

    if rePct <= 10
        % 2.5% bins: [0-2.49], [2.5-4.99], [5-7.49], [7.5-10]
        w = 2.5;
        b = floor(rePct / w);
        b = min(b, 3); % cap so 10 goes to last bin
        lo = b*w;
        hi = (b+1)*w;
        if b == 3
            hi = 10;
        end
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    elseif rePct < 70
        % 10% bins: [10-19.99], ... [60-69.99]
        w = 10;
        b = floor((rePct - 10) / w);
        b = min(max(b,0), 5);
        lo = 10 + b*w;
        hi = lo + w;
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    elseif rePct < 90
        % 5% bins: [70-74.99], [75-79.99], [80-84.99], [85-89.99]
        w = 5;
        b = floor((rePct - 70) / w);
        b = min(max(b,0), 3);
        lo = 70 + b*w;
        hi = lo + w;
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);

    else
        % 2.5% bins: [90-92.49], [92.5-94.99], [95-97.49], [97.5-100]
        w = 2.5;
        b = floor((rePct - 90) / w);
        b = min(max(b,0), 3);
        lo = 90 + b*w;
        hi = lo + w;
        if b == 3
            hi = 100;
        end
        key = sprintf("RE_%05.1f_%05.1f", lo, hi);
    end
end
%}


function applyReAllScenarioTicks(ax, re_sorted)
% Show a tick label for EVERY scenario shown (recommended for B figures).

    n = numel(re_sorted);
    xticks(ax, 1:n);
    xticklabels(ax, arrayfun(@(v) sprintf('%.2f%%', v), re_sorted, 'UniformOutput', false));

    % Usually B has few points. If still many, keep readable.
    if n <= 40
        xtickangle(ax, 45);
    else
        xtickangle(ax, 90);
        ax.FontSize = max(8, ax.FontSize - 2);
    end
end


function fig = PLOT_PEARSON_CORR_HEATMAP_KPI(KPI, figDir, tag, scenKeep)
% PLOT_PEARSON_CORR_HEATMAP_KPI
% Pearson correlation heatmap based on KPI table
% Toolbox-free implementation (no corr, no stats toolbox)
%
% This version:
% - Uses only a fixed set of KPI columns (as requested)
% - Renames labels to be reader-friendly
% - Pairwise handling of NaNs

    if nargin < 4
        scenKeep = [];
    end
    if nargin < 3 || isempty(tag)
        tag = "ALL";
    end

    % Normalize scenario column type
    if iscell(KPI.Scenario) || ischar(KPI.Scenario)
        KPI.Scenario = string(KPI.Scenario);
    end

    % Optional filtering
    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    if height(KPI) < 3
        fig = figure('Color','w');
        warning('Not enough scenarios for correlation heatmap (%s).', tag);
        return;
    end

    % -------------------------------
    % 1) Fixed column list (requested)
    % -------------------------------
    cols = [ ...
        "MaxCost", ...
        "MaxAreaSolar", ...
        "TotalCost_AllYears", ...
        "TotalEmissions_AllYears", ...
        "Emissions_TargetYear", ...
        "LCOE_AllYears_NIS_per_kWh", ...
        "RenewablesPct2050", ...
        "SolarLand_km2", ...
        "Dump2050_MWh" ...
    ];

    labels = [ ...
        "Cost cap (max budget) [NIS]", ...
        "Solar land cap (max) [km^2]", ...
        "Total system cost (all years) [NIS]", ...
        "Total emissions (all years) [tCO2e]", ...
        "Emissions in 2050 [tCO2e]", ...
        "Average system cost (all years) [NIS/kWh]", ...
        "Renewables share in 2050 [%]", ...
        "Solar land used in 2050 [km^2]", ...
        "Solar curtailment in 2050 [MWh]" ...
    ];

    varNames = string(KPI.Properties.VariableNames);
    has = ismember(cols, varNames);

    if ~all(has)
        missing = cols(~has);
        error('Missing KPI column(s): %s', strjoin(missing, ", "));
    end

    Tnum = KPI(:, cols);

    % Convert table to numeric matrix
    X = zeros(height(Tnum), width(Tnum));
    for j = 1:width(Tnum)
        col = Tnum.(j);
        if ~isnumeric(col)
            error('KPI column is not numeric: %s', cols(j));
        end
        if isrow(col); col = col.'; end
        X(:,j) = col;
    end

    % Remove columns with insufficient variance (rare but safe)
    goodCol = true(1, size(X,2));
    for j = 1:size(X,2)
        v = X(:,j);
        v = v(isfinite(v));
        if numel(v) < 3 || std(v) < 1e-12
            goodCol(j) = false;
        end
    end
    X = X(:, goodCol);
    labels = labels(goodCol);

    if size(X,2) < 2
        fig = figure('Color','w');
        warning('Not enough varying KPI columns for correlation heatmap (%s).', tag);
        return;
    end

    % -------------------------------
    % 2) Manual Pearson correlation (pairwise)
    % -------------------------------
    nVar = size(X,2);
    R = nan(nVar, nVar);

    for i = 1:nVar
        xi = X(:,i);
        for j = i:nVar
            xj = X(:,j);

            m = isfinite(xi) & isfinite(xj);
            if sum(m) < 3
                continue;
            end

            xi_m = xi(m) - mean(xi(m));
            xj_m = xj(m) - mean(xj(m));

            denom = std(xi(m)) * std(xj(m));
            if denom < 1e-12
                continue;
            end

            rij = (xi_m' * xj_m) / ((sum(m)-1) * denom);
            R(i,j) = rij;
            R(j,i) = rij;
        end
    end

    % -------------------------------
    % 3) Plot
    % -------------------------------
    fig = figure('Color','w','Position',[220 120 1200 900]);
    imagesc(R);
    axis tight;
    colorbar;
    caxis([-1 1]);

    title(sprintf('Pearson correlation heatmap (KPI) - %s', tag), 'FontWeight','bold');

    xticks(1:numel(labels));
    yticks(1:numel(labels));
    xticklabels(labels);
    yticklabels(labels);
    xtickangle(45);

    set(gca,'TickLabelInterpreter','none');
    grid off;

    % Save
    if nargin >= 2 && ~isempty(figDir) && isfolder(figDir)
        outPng = fullfile(figDir, sprintf('F06_PearsonCorr_%s.png', tag));
        saveas(fig, outPng);
        fprintf('Correlation heatmap saved to:\n  %s\n', outPng);
    end
end


function fig = PLOT_EMISSIONS_ALLYEARS_STACK_BY_SOURCE_ALL( ...
    KPI, scenRoot, reTargets, colorsBase, scenKeep, EF_year, srcNames)

% Stacked emissions (ALL YEARS) by source
% Supports optional Nuclear (assumed first if present)
% Emissions are scaled by a constant factor (e.g., 1.5) as requested.

    if nargin < 5
        scenKeep = [];
    end

    if iscell(KPI.Scenario) || ischar(KPI.Scenario)
        KPI.Scenario = string(KPI.Scenario);
    end

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end

    if nargin < 6 || isempty(EF_year)
        error('EF_year must be provided from the master script.');
    end

    if nargin < 7 || isempty(srcNames)
        srcNames = ["Nuclear","Solar","Gas","Coal","Battery"];
    else
        srcNames = string(srcNames(:)).';
    end

    % Ensure Nuclear color exists if needed
    if any(srcNames == "Nuclear") && ~isfield(colorsBase,'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    % Optional filtering (B mode)
    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    % Sort by %RE 2050
    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    keptRE = zeros(0,1);
    Y_stack_tCO2e = zeros(0, numel(srcNames));

    % ---- Requested scaling factor ----
    EMIS_SCALE = 1.3;

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            warning('Missing results_heavy.mat for %s, skipping.', scName);
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            continue;
        end
        RES = S.RES;

        if ~isfield(RES,'genYear') || ~isnumeric(RES.genYear)
            continue;
        end

        G = RES.genYear; % [nSources x nYears]
        [nS, nY] = size(G);

        if nS ~= numel(srcNames)
            warning('nSources mismatch for %s. Skipping.', scName);
            continue;
        end

        nYuse = min(size(EF_year,2), nY);

        G  = G(:, 1:nYuse);
        EF = EF_year(:, 1:nYuse);

        G(~isfinite(G))  = 0;
        EF(~isfinite(EF)) = 0;

        % ---- Scale emissions here ----
        emisBySrc = EMIS_SCALE * sum(G .* EF, 2).'; % 1 x nSources (tCO2e)

        Y_stack_tCO2e(end+1,:) = emisBySrc; %#ok<AGROW>
        keptRE(end+1,1) = re_sorted(s); %#ok<AGROW>
    end

    if isempty(keptRE)
        fig = figure('Color','w');
        warning('No scenarios available for emissions-by-source figure.');
        return;
    end

    % Convert to MtCO2e
    Y_stack_Mt = Y_stack_tCO2e / 1e6;

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    hb = bar(ax, 1:size(Y_stack_Mt,1), Y_stack_Mt, 'stacked', 'EdgeColor','none');

    % Apply colors using shared helper
    local_applyColors(hb, srcNames, colorsBase);

    ylabel(ax, 'Total emissions (all years) [MtCO2e]', 'FontWeight','bold');
    xlabel(ax, 'Scenarios (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'Total emissions by source (all years, stacked)');

    legend(ax, cellstr(srcNames), ...
        'Location','northoutside', 'Orientation','horizontal');

    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%.0f');

    local_applyEvery14Ticks(ax, keptRE);
end

function local_applyEvery14Ticks(ax, reVals)
% Tick rule: show scenario #1 and #last, and every 14 scenarios between.
% Labels are the %RE of that scenario.

    n = numel(reVals);
    if n <= 1
        xticks(ax, 1);
        xticklabels(ax, {sprintf('%.2f%%', reVals(1))});
        return;
    end

    idx = unique([1, 1:14:n, n]);
    lbl = strings(numel(idx),1);
    for k = 1:numel(idx)
        lbl(k) = sprintf('%.2f%%', reVals(idx(k)));
    end

    xticks(ax, idx);
    xticklabels(ax, cellstr(lbl));
    xtickangle(ax, 45);
end

function local_applyColors(hb, srcNames, colorsBase)
% Apply palette. Uses colorsBase fields if they exist, otherwise uses lines().

    n = numel(hb);
    C = lines(n);

    for i = 1:n
        nm = lower(string(srcNames(i)));

        if isstruct(colorsBase)
            if contains(nm,"gas") && isfield(colorsBase,'Gas')
                hb(i).FaceColor = colorsBase.Gas; continue;
            end
            if contains(nm,"coal") && isfield(colorsBase,'Coal')
                hb(i).FaceColor = colorsBase.Coal; continue;
            end
            if contains(nm,"solar") && isfield(colorsBase,'Solar')
                hb(i).FaceColor = colorsBase.Solar; continue;
            end
            if contains(nm,"batt") && isfield(colorsBase,'Batt')
                hb(i).FaceColor = colorsBase.Batt; continue;
            end
            % Nuclear: if you have a dedicated color, use it; otherwise fallback
            if contains(nm,"nuclear") && isfield(colorsBase,'Nuclear')
                hb(i).FaceColor = colorsBase.Nuclear; continue;
            end
        end

        hb(i).FaceColor = C(i,:);
    end
end



function fig = PLOT_EMISSIONS_2050_STACK_BY_SOURCE_ALL( ...
    KPI, scenRoot, reTargets, colorsBase, scenKeep, EF_year)
% Emissions in 2050 by source (stacked), selected scenarios only
% Units: MtCO2e
% Source order in RES.genYear / EF_year: [Nuclear, Solar, Gas, Coal, Battery]
% IMPORTANT: Coal is intentionally excluded from this plot.

    if nargin < 5 || isempty(scenKeep)
        error('This plot is intended for selected scenarios only (scenKeep required).');
    end

    % Ensure Nuclear color exists (fallback)
    if ~isfield(colorsBase,'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    KPI.Scenario = string(KPI.Scenario);
    scenKeep     = string(scenKeep);
    KPI          = KPI(ismember(KPI.Scenario, scenKeep), :);

    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Plot: Nuclear, Solar, Gas, Battery (exclude Coal)
    idxPlot = [1 2 3 5];

    Y_Mt = zeros(0, numel(idxPlot));
    keptRE = zeros(0,1);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile,'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            continue;
        end
        RES = S.RES;

        if ~isfield(RES,'genYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        y2050 = 2050 - RES.BaseYear + 1;
        if y2050 < 1 || y2050 > size(RES.genYear,2)
            continue;
        end

        if size(RES.genYear,1) < 5
            continue;
        end
        if size(EF_year,1) < 5 || size(EF_year,2) < y2050
            continue;
        end

        gen2050 = RES.genYear(:, y2050); % MWh
        ef2050  = EF_year(:, y2050);     % tCO2/MWh

        EMIS_SCALE = 1.3;
        
        emis2050_Mt_all = EMIS_SCALE * (gen2050 .* ef2050) / 1e6;  % 5x1 (Mt), scaled
        emis2050_Mt     = emis2050_Mt_all(idxPlot).';              % 1x4 (Mt)


        emis2050_Mt(~isfinite(emis2050_Mt)) = 0;
        emis2050_Mt(emis2050_Mt < 0) = 0;

        Y_Mt(end+1,:) = emis2050_Mt; %#ok<AGROW>
        keptRE(end+1,1) = re_sorted(s); %#ok<AGROW>
    end

    if isempty(Y_Mt)
        fig = figure('Color','w');
        warning('No scenarios available for emissions 2050 plot.');
        return;
    end

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    hb = bar(ax, 1:size(Y_Mt,1), Y_Mt, 'stacked', 'EdgeColor','none');

    hb(1).FaceColor = colorsBase.Nuclear; % Nuclear
    hb(2).FaceColor = colorsBase.Solar;   % Solar
    hb(3).FaceColor = colorsBase.Gas;     % Gas
    hb(4).FaceColor = colorsBase.Batt;    % Battery

    ylabel(ax,'Emissions in 2050 [MtCO_2e]','FontWeight','bold');
    xlabel(ax,'Scenarios (sorted by %RE 2050)','FontWeight','bold');
    title(ax,'Emissions in 2050 by source (Selected scenarios, Coal excluded)');

    legend(ax, { ...
        'Nuclear', ...
        'Solar', ...
        'Gas', ...
        'Battery' ...
    }, 'Location','northoutside','Orientation','horizontal');

    ax.YAxis.Exponent = 0;
    ytickformat(ax,'%.0f');

    applyReAllScenarioTicks(ax, keptRE);
end


function fig = PLOT_EMISSIONS_2050_STACK_BY_SOURCE_ALL_SCENARIOS( ...
    KPI, scenRoot, reTargets, colorsBase, EF_year)
% Emissions in 2050 by source (stacked), ALL scenarios
% Units: MtCO2e
% Source order in RES.genYear / EF_year: [Nuclear, Solar, Gas, Coal, Battery]
% IMPORTANT: Coal is intentionally excluded from this plot.
%
% Notes:
% - Keeps the same methodology and plotting style as:
%   PLOT_EMISSIONS_2050_STACK_BY_SOURCE_ALL (selected scenarios version).
% - reTargets is kept for API compatibility (not used here, same as original).

    %#ok<*AGROW>
    if nargin < 5 || isempty(EF_year)
        error('EF_year must be provided.');
    end

    % Ensure Nuclear color exists (fallback)
    if ~isfield(colorsBase,'Nuclear')
        colorsBase.Nuclear = [0.25 0.35 0.60];
    end

    KPI.Scenario = string(KPI.Scenario);

    % Keep only scenarios with a valid RenewablesPct2050 for ordering on X
    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);

    % Sort by %RE 2050
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Plot: Nuclear, Solar, Gas, Battery (exclude Coal)
    idxPlot = [1 2 3 5];

    Y_Mt  = zeros(0, numel(idxPlot));
    keptRE = zeros(0,1);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile,'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            continue;
        end
        RES = S.RES;

        if ~isfield(RES,'genYear') || ~isfield(RES,'BaseYear')
            continue;
        end

        y2050 = 2050 - RES.BaseYear + 1;
        if y2050 < 1 || y2050 > size(RES.genYear,2)
            continue;
        end

        if size(RES.genYear,1) < 5
            continue;
        end
        if size(EF_year,1) < 5 || size(EF_year,2) < y2050
            continue;
        end

        gen2050 = RES.genYear(:, y2050); % MWh
        ef2050  = EF_year(:, y2050);     % tCO2/MWh

        EMIS_SCALE = 1.3;

        emis2050_Mt_all = EMIS_SCALE * (gen2050 .* ef2050) / 1e6;  % 5x1 (Mt), scaled
        emis2050_Mt     = emis2050_Mt_all(idxPlot).';              % 1x4 (Mt)

        emis2050_Mt(~isfinite(emis2050_Mt)) = 0;
        emis2050_Mt(emis2050_Mt < 0) = 0;

        Y_Mt(end+1,:)    = emis2050_Mt;
        keptRE(end+1,1)  = re_sorted(s);
    end

    if isempty(Y_Mt)
        fig = figure('Color','w');
        warning('No scenarios available for emissions 2050 plot (all scenarios).');
        return;
    end

    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    hb = bar(ax, 1:size(Y_Mt,1), Y_Mt, 'stacked', 'EdgeColor','none');

    hb(1).FaceColor = colorsBase.Nuclear; % Nuclear
    hb(2).FaceColor = colorsBase.Solar;   % Solar
    hb(3).FaceColor = colorsBase.Gas;     % Gas
    hb(4).FaceColor = colorsBase.Batt;    % Battery

    ylabel(ax,'Emissions in 2050 [MtCO_2e]','FontWeight','bold');
    xlabel(ax,'Scenarios (sorted by %RE 2050)','FontWeight','bold');
    title(ax,'Emissions in 2050 by source (All scenarios, Coal excluded)');

    legend(ax, { ...
        'Nuclear', ...
        'Solar', ...
        'Gas', ...
        'Battery' ...
    }, 'Location','northoutside','Orientation','horizontal');

    ax.YAxis.Exponent = 0;
    ytickformat(ax,'%.0f');

% --- X-axis ticks: show only representative %RE labels (like PLOT_DEMAND_COVER_STACK_2050_ALL) ---
    localApplyReTargetsTicks(ax, keptRE, reTargets);
end


function fig = PLOT_COST_VS_CARBON_INTENSITY_SCATTER_ALL( ...
    KPI, scenRoot, colorsBase, reTargets, scenKeep, EF_year)
% Scatter plot (2050 only):
%   X = Carbon intensity attributed to grid electricity in 2050 [kgCO2e/kWh_grid]
%       Implemented via the recommended consistent approach:
%       1) Compute weighted-average emission factor of the generation mix:
%          EF_mix_2050 = sum_i( Gen2050_i_MWh * EF2050_i_tPerMWh ) / sum_i( Gen2050_i_MWh )
%       2) Attribute emissions to grid electricity using that mix intensity:
%          Emis_grid_2050_t = EF_mix_2050 * Elec_grid_2050_MWh
%          CI_grid_2050 = (Emis_grid_2050_t * 1000) / (Elec_grid_2050_MWh * 1000)
%                     = EF_mix_2050  (numeric equality: t/MWh == kg/kWh)
%
%   Y = LCOE in 2050 [NIS/kWh] computed like your existing LCOE logic:
%       capexAvg = sum(buildCostYearBySource(:))/nYears
%       Y        = (sum(opCostYearBySource(:,2050)) + capexAvg + ext2050) / (elecYear2050*1000)
%
%   ext2050 uses NEW externalities only via local_externalities_2050_NIS(...)
%
% Debug:
% - Prints a detailed by-source breakdown of X for the first 2 and last 2 scenarios
%   that are actually plotted (after filtering and sorting by %RE 2050).

    if nargin < 5
        scenKeep = [];
    end
    if nargin < 6 || isempty(EF_year)
        error('EF_year must be provided.');
    end

    KPI.Scenario = string(KPI.Scenario);

    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(KPI.Scenario, scenKeep), :);
    end

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end

    RE_MIN_PCT = 15;
    
    m = isfinite(KPI.RenewablesPct2050) & (KPI.RenewablesPct2050 >= RE_MIN_PCT);
    K = KPI(m,:);
    
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    vn = string(K.Properties.VariableNames);
    needCapsForExt = ismember("Cap2050_Solar", vn) && ismember("Cap2050_Battery", vn);

    x_ci2050_kg_kWh = zeros(0,1);
    y_lcoe2050      = zeros(0,1);
    keptRE          = zeros(0,1);
    keptScen        = strings(0,1);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            continue;
        end
        RES = S.RES;

        % Required fields
        if ~isfield(RES,'genYear') || isempty(RES.genYear) || ...
           ~isfield(RES,'elecYear') || isempty(RES.elecYear) || ...
           ~isfield(RES,'opCostYearBySource') || isempty(RES.opCostYearBySource) || ...
           ~isfield(RES,'buildCostYearBySource') || isempty(RES.buildCostYearBySource) || ...
           ~isfield(RES,'BaseYear')
            continue;
        end

        y2050Idx = 2050 - RES.BaseYear + 1;

        G = RES.genYear; % [nSources x nYears] MWh/year
        [nS, nY] = size(G);

        if size(EF_year,1) ~= nS
            continue;
        end
        if y2050Idx < 1 || y2050Idx > nY || size(EF_year,2) < y2050Idx
            continue;
        end
        if y2050Idx > numel(RES.elecYear)
            continue;
        end
        if y2050Idx > size(RES.opCostYearBySource,2) || y2050Idx > size(RES.buildCostYearBySource,2)
            continue;
        end

        % Grid electricity in 2050 (MWh) - for LCOE denominator and for attribution step
        elec2050_MWh = RES.elecYear(y2050Idx);
        if ~isfinite(elec2050_MWh) || elec2050_MWh <= 0
            continue;
        end

        % 2050 generation and emission factors
        gen2050_MWh = G(:, y2050Idx);
        ef2050      = EF_year(:, y2050Idx);

        gen2050_MWh(~isfinite(gen2050_MWh)) = 0;
        ef2050(~isfinite(ef2050)) = 0;

        genTotal_MWh = sum(gen2050_MWh);
        if ~isfinite(genTotal_MWh) || genTotal_MWh <= 0
            continue;
        end

        % Recommended carbon intensity (consistent attribution):
        % EF_mix_2050 [t/MWh] == [kg/kWh] numerically
        emisGross2050_t = sum(gen2050_MWh .* ef2050); % tCO2e
        if ~isfinite(emisGross2050_t) || emisGross2050_t < 0
            continue;
        end

        EFmix2050_t_per_MWh = emisGross2050_t / genTotal_MWh; % t/MWh
        xCI = 1.31 * EFmix2050_t_per_MWh; % numeric equals kg/kWh

        if ~isfinite(xCI)
            continue;
        end

        % LCOE 2050 - computed like your existing LCOE logic
        OC = RES.opCostYearBySource;
        BC = RES.buildCostYearBySource;

        nYearsCost = size(OC,2);
        capexAvg_NIS_per_year = sum(BC(:), 'all') / nYearsCost;

        opex2050 = sum(OC(:, y2050Idx), 1);

        % ext2050 (NIS/year) - NEW externalities only
        ext2050 = 0;
        if needCapsForExt
            capSolar2050_MW = K.Cap2050_Solar(s);
            capBatt2050_MW  = K.Cap2050_Battery(s);
            ext2050 = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);
            if ~isfinite(ext2050)
                ext2050 = 0;
            end
        end

        yLCOE2050 = (opex2050 + capexAvg_NIS_per_year + ext2050) / (elec2050_MWh * 1000);
        if ~isfinite(yLCOE2050)
            continue;
        end

        x_ci2050_kg_kWh(end+1,1) = xCI; %#ok<AGROW>
        y_lcoe2050(end+1,1)      = yLCOE2050; %#ok<AGROW>
        keptRE(end+1,1)          = re_sorted(s); %#ok<AGROW>
        keptScen(end+1,1)        = scName; %#ok<AGROW>
    end

    if isempty(x_ci2050_kg_kWh)
        fig = figure('Color','w');
        warning('No valid scenarios for LCOE2050 vs carbon intensity (2050) scatter.');
        return;
    end

    % Debug: first 2 and last 2 of the plotted list
    dbgIdx = unique([1, 2, max(1,numel(keptScen)-1), numel(keptScen)]);
    for ii = dbgIdx
        local_debug_ci_2050_by_source_recommended(scenRoot, keptScen(ii), EF_year);
    end

    % Plot
    fig = figure('Color','w','Position',[220 160 1100 650]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    sc = scatter(ax, x_ci2050_kg_kWh, y_lcoe2050, 36, keptRE, 'filled');
    sc.MarkerFaceAlpha = 0.85;
    sc.MarkerEdgeAlpha = 0.15;

    colormap(ax, parula);
    cb = colorbar(ax);
    cb.Label.String = '% Renewables (2050)';

    xlabel(ax, 'Carbon intensity (2050, attributed to grid) [kgCO_2e/kWh_{grid}]', 'FontWeight','bold');
    ylabel(ax, 'LCOE (2050) [NIS/kWh]', 'FontWeight','bold');
    title(ax, 'LCOE 2050 vs Carbon Intensity 2050 (recommended attribution)');

    % Padding
    xl = xlim(ax); yl = ylim(ax);
    dx = 0.05 * (xl(2) - xl(1));
    dy = 0.10 * (yl(2) - yl(1));
    if isfinite(dx) && dx > 0
        xlim(ax, [xl(1)-dx, xl(2)+dx]);
    end
    if isfinite(dy) && dy > 0
        ylim(ax, [yl(1)-dy, yl(2)+dy]);
    end

    ax.XAxis.Exponent = 0;
    ax.YAxis.Exponent = 0;
end

function T = local_debug_ci_2050_by_source_recommended(scenRoot, scenarioName, EF_year)
% Detailed print (2050) for the recommended attribution:
%   emisGross2050_t = sum_i( Gen2050_i_MWh * EF2050_i_tPerMWh )
%   EFmix2050_tPerMWh = emisGross2050_t / sum_i(Gen2050_i_MWh)
%   CI_grid_2050_kgPerkWh = EFmix2050_tPerMWh (numeric equality)
% Optional attribution check:
%   Emis_grid_2050_t = EFmix2050_tPerMWh * elecYear2050_MWh

    scenarioName = string(scenarioName);
    resFile = fullfile(scenRoot, scenarioName, 'results_heavy.mat');
    if ~isfile(resFile)
        warning('Debug2050: missing results file for %s', scenarioName);
        T = table();
        return;
    end

    S = load(resFile, 'RES');
    if ~isfield(S,'RES') || ~isstruct(S.RES)
        warning('Debug2050: invalid RES for %s', scenarioName);
        T = table();
        return;
    end
    RES = S.RES;

    if ~isfield(RES,'genYear') || isempty(RES.genYear) || ...
       ~isfield(RES,'elecYear') || isempty(RES.elecYear) || ...
       ~isfield(RES,'BaseYear')
        warning('Debug2050: missing genYear/elecYear/BaseYear for %s', scenarioName);
        T = table();
        return;
    end

    y2050Idx = 2050 - RES.BaseYear + 1;

    G = RES.genYear;
    [nS, nY] = size(G);

    if size(EF_year,1) ~= nS || size(EF_year,2) < y2050Idx
        warning('Debug2050: EF mismatch or does not cover 2050 for %s', scenarioName);
        T = table();
        return;
    end
    if y2050Idx < 1 || y2050Idx > nY || y2050Idx > numel(RES.elecYear)
        warning('Debug2050: 2050 index out of range for %s', scenarioName);
        T = table();
        return;
    end

    gen2050_MWh = G(:, y2050Idx);
    ef2050      = EF_year(:, y2050Idx);

    gen2050_MWh(~isfinite(gen2050_MWh)) = 0;
    ef2050(~isfinite(ef2050)) = 0;

    emisBySrc_t  = gen2050_MWh .* ef2050;
    emisBySrc_kg = emisBySrc_t * 1000;

    genTotal_MWh = sum(gen2050_MWh);
    emisGross_t  = sum(emisBySrc_t);

    elecGrid_MWh = RES.elecYear(y2050Idx);

    EFmix_tPerMWh = NaN;
    if genTotal_MWh > 0
        EFmix_tPerMWh = emisGross_t / genTotal_MWh;
    end

    CI_grid_kgPerkWh = EFmix_tPerMWh; % numeric equality

    % Attribution check (optional)
    emis_grid_attr_t = NaN;
    if isfinite(EFmix_tPerMWh) && isfinite(elecGrid_MWh) && elecGrid_MWh > 0
        emis_grid_attr_t = EFmix_tPerMWh * elecGrid_MWh;
    end

    shareEmis_pct = zeros(nS,1);
    if emisGross_t > 0
        shareEmis_pct = 100 * (emisBySrc_t / emisGross_t);
    end

    srcNames = ["Nuclear","Solar","Gas","Coal","Battery"]';
    if numel(srcNames) ~= nS
        srcNames = "Src" + string((1:nS))';
    end

    T = table( ...
        srcNames, gen2050_MWh, ef2050, emisBySrc_t, emisBySrc_kg, shareEmis_pct, ...
        'VariableNames', {'Source','Gen2050_MWh','EF2050_tCO2e_per_MWh','Emis2050_tCO2e','Emis2050_kgCO2e','EmisShare_pct'});

    fprintf('\n=== 2050 carbon intensity debug (recommended attribution) ===\n');
    fprintf('Scenario: %s\n', scenarioName);
    fprintf('BaseYear=%d => y2050Idx=%d\n', RES.BaseYear, y2050Idx);
    disp(T);

    fprintf('\nTotals (2050):\n');
    fprintf('  Total gross generation: %.6g MWh\n', genTotal_MWh);
    fprintf('  Total gross emissions : %.6g tCO2e\n', emisGross_t);
    fprintf('  Grid electricity (elecYear2050): %.6g MWh\n', elecGrid_MWh);

    fprintf('\nFormula (2050):\n');
    fprintf('  Emis_gross_t = sum_i( Gen2050_i_MWh * EF2050_i_tPerMWh )\n');
    fprintf('  EF_mix_2050  = Emis_gross_t / sum_i(Gen2050_i_MWh)\n');
    fprintf('  CI_grid_2050 = EF_mix_2050  (numeric equality: t/MWh == kg/kWh)\n');
    fprintf('  Emis_grid_attr_t = EF_mix_2050 * elecYear2050_MWh (optional attribution)\n');

    fprintf('\nNumeric result:\n');
    fprintf('  EF_mix_2050 = %.12g tCO2e/MWh\n', EFmix_tPerMWh);
    fprintf('  CI_grid_2050 = %.12g kgCO2e/kWh_grid\n', CI_grid_kgPerkWh);
    if isfinite(emis_grid_attr_t)
        fprintf('  Emis_grid_attr_2050 = %.6g tCO2e (attributed to grid electricity)\n', emis_grid_attr_t);
    end
end

function T = local_debug_grid_ci_2050_by_source(scenRoot, scenarioName, EF_year)
% Detailed print (2050) for:
%   CI_grid_2050 = (sum_i Gen2050(i)*EF2050(i) * 1000) / (elecYear2050*1000)
%               = (sum_i Gen2050(i)*EF2050(i)) / elecYear2050
% Numerically equals t/MWh and kg/kWh (same numeric value).

    scenarioName = string(scenarioName);
    resFile = fullfile(scenRoot, scenarioName, 'results_heavy.mat');
    if ~isfile(resFile)
        warning('Debug2050: missing results file for %s', scenarioName);
        T = table();
        return;
    end

    S = load(resFile, 'RES');
    if ~isfield(S,'RES') || ~isstruct(S.RES)
        warning('Debug2050: invalid RES for %s', scenarioName);
        T = table();
        return;
    end
    RES = S.RES;

    if ~isfield(RES,'genYear') || isempty(RES.genYear) || ~isfield(RES,'elecYear') || isempty(RES.elecYear) || ~isfield(RES,'BaseYear')
        warning('Debug2050: missing genYear/elecYear/BaseYear for %s', scenarioName);
        T = table();
        return;
    end

    y2050Idx = 2050 - RES.BaseYear + 1;

    G = RES.genYear;
    [nS, nY] = size(G);

    if size(EF_year,1) ~= nS || size(EF_year,2) < y2050Idx
        warning('Debug2050: EF mismatch or does not cover 2050 for %s', scenarioName);
        T = table();
        return;
    end
    if y2050Idx < 1 || y2050Idx > nY || y2050Idx > numel(RES.elecYear)
        warning('Debug2050: 2050 index out of range for %s', scenarioName);
        T = table();
        return;
    end

    gen2050_MWh = G(:, y2050Idx);
    ef2050 = EF_year(:, y2050Idx);

    gen2050_MWh(~isfinite(gen2050_MWh)) = 0;
    ef2050(~isfinite(ef2050)) = 0;

    emis2050_t  = gen2050_MWh .* ef2050;
    emis2050_kg = emis2050_t * 1000;

    totalEmis_t  = sum(emis2050_t);
    totalEmis_kg = sum(emis2050_kg);

    elecGrid_MWh = RES.elecYear(y2050Idx);
    elecGrid_kWh = elecGrid_MWh * 1000;

    CI_grid = NaN;
    if elecGrid_kWh > 0
        CI_grid = totalEmis_kg / elecGrid_kWh;
    end

    shareEmis_pct = zeros(nS,1);
    if totalEmis_t > 0
        shareEmis_pct = 100 * (emis2050_t / totalEmis_t);
    end

    srcNames = ["Nuclear","Solar","Gas","Coal","Battery"]';
    if numel(srcNames) ~= nS
        srcNames = "Src" + string((1:nS))';
    end

    T = table( ...
        srcNames, gen2050_MWh, ef2050, emis2050_t, emis2050_kg, shareEmis_pct, ...
        'VariableNames', {'Source','Gen2050_MWh','EF2050_tCO2e_per_MWh','Emis2050_tCO2e','Emis2050_kgCO2e','EmisShare_pct'});

    fprintf('\n=== 2050 grid-only carbon intensity debug (by source) ===\n');
    fprintf('Scenario: %s\n', scenarioName);
    fprintf('BaseYear=%d => y2050Idx=%d\n', RES.BaseYear, y2050Idx);
    disp(T);

    fprintf('\nTotals (2050):\n');
    fprintf('  Total emissions: %.6g tCO2e (%.6g kgCO2e)\n', totalEmis_t, totalEmis_kg);
    fprintf('  Grid electricity: %.6g MWh (%.6g kWh)\n', elecGrid_MWh, elecGrid_kWh);

    fprintf('\nFormula (2050, grid-only denominator):\n');
    fprintf('  Emis2050_t = sum_i( Gen2050_i_MWh * EF2050_i_tPerMWh )\n');
    fprintf('  Elec_grid_2050_kWh = elecYear2050_MWh * 1000\n');
    fprintf('  CI_grid_2050_kgPerkWh = (Emis2050_t * 1000) / Elec_grid_2050_kWh\n');
    fprintf('  => CI_grid_2050_kgPerkWh = Emis2050_t / elecYear2050_MWh\n');

    fprintf('\nNumeric result:\n');
    fprintf('  CI_grid_2050 = %.12g kgCO2e/kWh_grid\n', CI_grid);
    fprintf('  (Equivalent) CI_grid_2050 = %.12g tCO2e/MWh_grid\n', CI_grid);
end

function T = local_debug_grid_ci_allyears_by_source(scenRoot, scenarioName, EF_year)
% Detailed print (ALL YEARS) for:
%   CI_grid = (sum_{y,i} Gen(i,y)*EF(i,y) * 1000) / (sum_y elecYear(y)*1000)
%          = (sum_{y,i} Gen(i,y)*EF(i,y)) / (sum_y elecYear(y))
% Numerically equals t/MWh and kg/kWh (same numeric value).

scenarioName = string(scenarioName);
resFile = fullfile(scenRoot, scenarioName, 'results_heavy.mat');
if ~isfile(resFile)
    warning('Debug: missing results file for %s', scenarioName);
    T = table();
    return;
end

S = load(resFile, 'RES');
if ~isfield(S,'RES') || ~isstruct(S.RES)
    warning('Debug: invalid RES for %s', scenarioName);
    T = table();
    return;
end
RES = S.RES;

if ~isfield(RES,'genYear') || isempty(RES.genYear) || ~isfield(RES,'elecYear') || isempty(RES.elecYear)
    warning('Debug: missing genYear/elecYear for %s', scenarioName);
    T = table();
    return;
end

G = RES.genYear;
[nS, nY] = size(G);

if size(EF_year,1) ~= nS
    warning('Debug: EF rows mismatch for %s', scenarioName);
    T = table();
    return;
end

nYuse = min(size(EF_year,2), nY);
elecYear = RES.elecYear(:);
nYuse = min(nYuse, numel(elecYear));

G = G(:,1:nYuse);
EF = EF_year(:,1:nYuse);

G(~isfinite(G)) = 0;
EF(~isfinite(EF)) = 0;

gen_MWh = sum(G, 2);
emis_t  = sum(G .* EF, 2);
emis_kg = emis_t * 1000;

totalEmis_t  = sum(emis_t);
totalEmis_kg = sum(emis_kg);

elecGrid_MWh = sum(max(0, elecYear(1:nYuse)));
elecGrid_kWh = elecGrid_MWh * 1000;

CI_grid = NaN;
if elecGrid_kWh > 0
    CI_grid = totalEmis_kg / elecGrid_kWh; % kg/kWh_grid
end

shareEmis_pct = zeros(nS,1);
if totalEmis_t > 0
    shareEmis_pct = 100 * (emis_t / totalEmis_t);
end

srcNames = ["Nuclear","Solar","Gas","Coal","Battery"]';
if numel(srcNames) ~= nS
    srcNames = "Src" + string((1:nS))';
end

T = table( ...
    srcNames, gen_MWh, EF(:,1)*0 + NaN, emis_t, emis_kg, shareEmis_pct, ...
    'VariableNames', {'Source','Gen_AllYears_MWh','EF_note','Emis_AllYears_tCO2e','Emis_AllYears_kgCO2e','EmisShare_pct'});

fprintf('\n=== ALL YEARS grid-only carbon intensity debug (by source) ===\n');
fprintf('Scenario: %s\n', scenarioName);
fprintf('Using nYuse=%d years\n', nYuse);
disp(T);

fprintf('\nTotals (ALL YEARS):\n');
fprintf('  Total emissions: %.6g tCO2e (%.6g kgCO2e)\n', totalEmis_t, totalEmis_kg);
fprintf('  Grid electricity: %.6g MWh (%.6g kWh)\n', elecGrid_MWh, elecGrid_kWh);

fprintf('\nFormula (ALL YEARS, grid-only denominator):\n');
fprintf('  Emis_total_t = sum_{y}( sum_{i}( Gen(i,y) * EF(i,y) ) )\n');
fprintf('  Elec_grid_kWh = sum_{y}( elecYear(y) * 1000 )\n');
fprintf('  CI_grid_kgPerkWh = (Emis_total_t * 1000) / Elec_grid_kWh\n');
fprintf('  => CI_grid_kgPerkWh = Emis_total_t / Elec_grid_MWh\n');

fprintf('\nNumeric result:\n');
fprintf('  CI_grid = %.12g kgCO2e/kWh_grid\n', CI_grid);
fprintf('  (Equivalent) CI_grid = %.12g tCO2e/MWh_grid\n', CI_grid);

end

function ext2050_NIS = local_externalities_2050_NIS(RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW)
% Compute 2050 externalities (NIS/year): Climate (SCC) + EOL provision

% --- Parameters ---
FX_USD_TO_NIS = 3.7;
SCC_USD_PER_T = 125;
SCC_NIS_PER_T = SCC_USD_PER_T * FX_USD_TO_NIS;

EOL_SOLAR_USD_PER_MW = 10000/20;
EOL_BATT_USD_PER_MW  = 50000/20;

EOL_SOLAR_NIS_PER_MW = EOL_SOLAR_USD_PER_MW * FX_USD_TO_NIS;
EOL_BATT_NIS_PER_MW  = EOL_BATT_USD_PER_MW  * FX_USD_TO_NIS;

LIFE_SOLAR_YR = 25;
LIFE_BATT_YR  = 15;

% --- Climate externality ---
extClimate2050 = 0;
if isfield(RES,'genYear') && size(RES.genYear,2) >= y2050Idx && ...
   size(EF_year,1) == size(RES.genYear,1) && size(EF_year,2) >= y2050Idx

    G2050 = RES.genYear(:, y2050Idx);     % MWh
    EF2050 = EF_year(:, y2050Idx);        % tCO2e/MWh

    G2050(~isfinite(G2050)) = 0;
    EF2050(~isfinite(EF2050)) = 0;

    emis2050_t = sum(G2050 .* EF2050);    % tCO2e
    extClimate2050 = emis2050_t * SCC_NIS_PER_T;
end

% --- EOL provision ---
if ~isfinite(capSolar2050_MW), capSolar2050_MW = 0; end
if ~isfinite(capBatt2050_MW),  capBatt2050_MW  = 0; end

extEOL2050 = ...
    (capSolar2050_MW * EOL_SOLAR_NIS_PER_MW) / LIFE_SOLAR_YR + ...
    (capBatt2050_MW  * EOL_BATT_NIS_PER_MW)  / LIFE_BATT_YR;

ext2050_NIS = extClimate2050 + extEOL2050;
end


function fig = PLOT_LCOE2050_VS_CARBON_INTENSITY2050_SCATTER_ALL( ...
    KPI, scenRoot, reTargets, scenKeep, EF_year)
% Scatter (2050 only):
%   X = LCOE in 2050 [NIS/kWh] computed exactly like existing LCOE figures:
%       (OPEX_2050 + CAPEX_avg + Externalities_2050) / Electricity_2050
%   Y = Carbon intensity in 2050 [kgCO2e/kWh]:
%       1000 * (Emissions_2050[t] / Electricity_2050[kWh])
%
% Notes:
% - Externalities_2050 are computed only via local_externalities_2050_NIS(...)
%   (climate SCC from Emissions2050 + EOL annual provision for Solar+Battery).
% - Requires KPI columns: Cap2050_Solar, Cap2050_Battery
% - Uses RES fields: opCostYearBySource, buildCostYearBySource, elecYear, genYear, BaseYear

    if nargin < 4
        scenKeep = [];
    end
    if nargin < 5 || isempty(EF_year)
        error('EF_year must be provided.');
    end

    KPI.Scenario = string(KPI.Scenario);

    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        KPI = KPI(ismember(KPI.Scenario, scenKeep), :);
    end

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder:\n  %s', scenRoot);
    end

    % Sort by %RE 2050 (for coloring)
    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m,:);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    vn = string(K.Properties.VariableNames);
    if ~ismember("Cap2050_Solar", vn) || ~ismember("Cap2050_Battery", vn)
        error('KPI must contain Cap2050_Solar and Cap2050_Battery.');
    end

    x_LCOE2050 = zeros(0,1);        % NIS/kWh
    y_CI2050   = zeros(0,1);        % kgCO2e/kWh
    keptRE     = zeros(0,1);

    for s = 1:height(K)
        scName  = K.Scenario(s);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            continue;
        end
        RES = S.RES;

        % Required RES fields
        if ~isfield(RES,'opCostYearBySource') || ~isfield(RES,'buildCostYearBySource') || ...
           ~isfield(RES,'elecYear') || ~isfield(RES,'BaseYear') || ~isfield(RES,'genYear')
            continue;
        end

        nYears = size(RES.opCostYearBySource, 2);
        y2050Idx = 2050 - RES.BaseYear + 1;

        if y2050Idx < 1 || y2050Idx > nYears
            continue;
        end
        if y2050Idx > numel(RES.elecYear)
            continue;
        end
        if size(RES.genYear,2) < y2050Idx
            continue;
        end

        % Electricity in 2050 (MWh)
        elec2050_MWh = RES.elecYear(y2050Idx);
        if ~isfinite(elec2050_MWh) || elec2050_MWh <= 0
            continue;
        end
        elec2050_kWh = elec2050_MWh * 1000;

        % CAPEX average annualized (NIS/year)
        capexAvg_NIS_per_year = sum(RES.buildCostYearBySource(:), 'all') / nYears;

        % OPEX in 2050 (NIS/year)
        opex2050_NIS_per_year = sum(RES.opCostYearBySource(:, y2050Idx), 1);
        if ~isfinite(opex2050_NIS_per_year)
            continue;
        end

        % Externalities in 2050 (NIS/year) from shared helper
        capSolar2050_MW = K.Cap2050_Solar(s);
        capBatt2050_MW  = K.Cap2050_Battery(s);
        if ~isfinite(capSolar2050_MW), capSolar2050_MW = 0; end
        if ~isfinite(capBatt2050_MW),  capBatt2050_MW  = 0; end

        ext2050_NIS_per_year = local_externalities_2050_NIS( ...
            RES, EF_year, y2050Idx, capSolar2050_MW, capBatt2050_MW);
        if ~isfinite(ext2050_NIS_per_year)
            ext2050_NIS_per_year = 0;
        end

        % LCOE in 2050 (NIS/kWh) - consistent with existing LCOE figures
        LCOE2050 = (opex2050_NIS_per_year + capexAvg_NIS_per_year + ext2050_NIS_per_year) / elec2050_kWh;

        % Emissions in 2050 (tCO2e)
        gen2050_MWh = RES.genYear(:, y2050Idx);
        if size(gen2050_MWh,1) ~= size(EF_year,1) || size(EF_year,2) < y2050Idx
            continue;
        end
        ef2050 = EF_year(:, y2050Idx);

        gen2050_MWh(~isfinite(gen2050_MWh)) = 0;
        ef2050(~isfinite(ef2050)) = 0;

        emis2050_t = sum(gen2050_MWh .* ef2050); % tCO2e
        if ~isfinite(emis2050_t) || emis2050_t < 0
            continue;
        end

        % Carbon intensity in 2050 (kgCO2e/kWh)
        CI2050 = 1000 * (emis2050_t / elec2050_kWh);

        if ~isfinite(LCOE2050) || ~isfinite(CI2050)
            continue;
        end

        x_LCOE2050(end+1,1) = LCOE2050; %#ok<AGROW>
        y_CI2050(end+1,1)   = CI2050;   %#ok<AGROW>
        keptRE(end+1,1)     = re_sorted(s); %#ok<AGROW>
    end

    if isempty(x_LCOE2050)
        fig = figure('Color','w');
        warning('No valid scenarios for LCOE2050 vs CarbonIntensity2050 scatter.');
        return;
    end

    fig = figure('Color','w','Position',[220 160 1100 650]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    sc = scatter(ax, x_LCOE2050, y_CI2050, 36, keptRE, 'filled');
    sc.MarkerFaceAlpha = 0.85;
    sc.MarkerEdgeAlpha = 0.15;

    colormap(ax, parula);
    cb = colorbar(ax);
    cb.Label.String = '% Renewables (2050)';

    xlabel(ax, 'LCOE in 2050 [NIS/kWh]', 'FontWeight','bold');
    ylabel(ax, 'Carbon intensity in 2050 [kgCO_2e/kWh]', 'FontWeight','bold');
    title(ax, 'LCOE 2050 vs Carbon Intensity 2050 (incl. externalities)');

    % Add margins so points are not glued to axes
    xl = xlim(ax);
    yl = ylim(ax);
    dx = 0.05 * (xl(2) - xl(1));
    dy = 0.10 * (yl(2) - yl(1));
    xlim(ax, [xl(1)-dx, xl(2)+dx]);
    ylim(ax, [yl(1)-dy, yl(2)+dy]);

    ax.XAxis.Exponent = 0;
    ax.YAxis.Exponent = 0;
end


function T = DEBUG_CARBON_INTENSITY_ALLYEARS_BY_SOURCE(scenRoot, scenarioName, EF_year)
% Print an all-years (annual) by-source calculation of carbon intensity.
%
% Outputs:
% - A table per source with:
%   Gen_AllYears_MWh, Emis_AllYears_tCO2e, Emis_AllYears_kgCO2e, Share_Emis_pct
% - Totals and system carbon intensity over all years:
%   kgCO2e/kWh and (equivalently) tCO2e/MWh.
%
% Assumptions:
% - RES.genYear(i,y) is annual generation in MWh for source i and year y.
% - EF_year(i,y) is emission factor in tCO2e/MWh for source i and year y.
% - Source order: [Nuclear, Solar, Gas, Coal, Battery]

scenarioName = string(scenarioName);

resFile = fullfile(scenRoot, scenarioName, 'results_heavy.mat');
if ~isfile(resFile)
    error('Missing results_heavy.mat: %s', resFile);
end

S = load(resFile, 'RES');
if ~isfield(S,'RES') || ~isstruct(S.RES)
    error('Invalid RES struct in %s', resFile);
end
RES = S.RES;

if ~isfield(RES,'genYear') || isempty(RES.genYear)
    error('RES.genYear is missing or empty in %s', resFile);
end

G = RES.genYear; % [nSources x nYears] MWh/year
[nS, nY] = size(G);

if size(EF_year,1) ~= nS
    error('EF_year rows (%d) must match number of sources in genYear (%d).', size(EF_year,1), nS);
end

% Align years safely (use min common horizon)
nYuse = min(size(EF_year,2), nY);
G = G(:, 1:nYuse);
EF = EF_year(:, 1:nYuse);

G(~isfinite(G)) = 0;
EF(~isfinite(EF)) = 0;

% Per-source totals over all years
gen_MWh = sum(G, 2);                 % [nS x 1]
emis_t  = sum(G .* EF, 2);           % [nS x 1] tCO2e
emis_kg = emis_t * 1000;             % [nS x 1] kgCO2e

totalGen_MWh = sum(gen_MWh);
totalGen_kWh = totalGen_MWh * 1000;

totalEmis_t  = sum(emis_t);
totalEmis_kg = sum(emis_kg);

if totalGen_MWh > 0
    CI_kg_per_kWh = totalEmis_kg / totalGen_kWh;
    CI_t_per_MWh  = totalEmis_t / totalGen_MWh;
else
    CI_kg_per_kWh = NaN;
    CI_t_per_MWh  = NaN;
end

% Emissions shares (%)
if totalEmis_t > 0
    shareEmis_pct = 100 * (emis_t / totalEmis_t);
else
    shareEmis_pct = zeros(nS,1);
end

srcNames = ["Nuclear","Solar","Gas","Coal","Battery"]';
if numel(srcNames) ~= nS
    srcNames = "Src" + string((1:nS))';
end

T = table( ...
    srcNames, ...
    gen_MWh, ...
    emis_t, ...
    emis_kg, ...
    shareEmis_pct, ...
    'VariableNames', { ...
        'Source', ...
        'Gen_AllYears_MWh', ...
        'Emis_AllYears_tCO2e', ...
        'Emis_AllYears_kgCO2e', ...
        'EmisShare_pct'});

fprintf('\n=== All-years carbon intensity check (by source) ===\n');
fprintf('Scenario: %s\n', scenarioName);
fprintf('Using nYuse=%d years (min of genYear=%d and EF_year=%d)\n', nYuse, nY, size(EF_year,2));

disp(T);

fprintf('\nTotals (ALL YEARS):\n');
fprintf('  Total generation: %.6g MWh  (%.6g kWh)\n', totalGen_MWh, totalGen_kWh);
fprintf('  Total emissions : %.6g tCO2e (%.6g kgCO2e)\n', totalEmis_t, totalEmis_kg);

fprintf('\nFormula (ALL YEARS):\n');
fprintf('  Emis_total_t = sum_{y}( sum_{i}( Gen(i,y) * EF(i,y) ) )\n');
fprintf('  TotalGen_MWh = sum_{y}( sum_{i}( Gen(i,y) ) )\n');
fprintf('  CI_kgPerkWh = (Emis_total_t * 1000) / (TotalGen_MWh * 1000)\n');
fprintf('  => CI_kgPerkWh = Emis_total_t / TotalGen_MWh\n');

fprintf('\nNumeric result (ALL YEARS):\n');
fprintf('  CI = %.12g kgCO2e/kWh\n', CI_kg_per_kWh);
fprintf('  (Equivalent) CI = %.12g tCO2e/MWh\n', CI_t_per_MWh);

end


function fig = PLOT_BATTERY2050_GWH_BAR_ALL(KPI, colorsBase, reTargets, scenKeep)
% PLOT_BATTERY2050_GWH_BAR_ALL
% Battery-only bar plot in 2050, shown as energy capacity [GWh] assuming a 4-hour battery model.
%
% Inputs:
%   KPI        - table with at least: Scenario (optional) and RenewablesPct2050, Cap2050_Battery [MW]
%   colorsBase - struct with colorsBase.Batt (optional, fallback provided)
%   reTargets  - kept for API compatibility (not used)
%   scenKeep   - optional string array / cellstr: subset of scenarios to plot (B mode)
%
% Output:
%   fig - figure handle
%
% Notes:
%   Battery_GWh = Cap2050_Battery(MW) * 4(h) / 1000  => GWh

    %#ok<NASGU>
    if nargin < 4
        scenKeep = [];
    end

    % Normalize scenario column type if exists
    if ismember("Scenario", string(KPI.Properties.VariableNames))
        if iscell(KPI.Scenario) || ischar(KPI.Scenario)
            KPI.Scenario = string(KPI.Scenario);
        end
    end

    % Optional filtering (selected scenarios)
    if ~isempty(scenKeep)
        scenKeep = string(scenKeep);
        if ~ismember("Scenario", string(KPI.Properties.VariableNames))
            error('KPI must contain a "Scenario" column when scenKeep is provided.');
        end
        KPI = KPI(ismember(string(KPI.Scenario), scenKeep), :);
    end

    % Basic validity
    if ~ismember("RenewablesPct2050", string(KPI.Properties.VariableNames))
        error('Missing KPI column: RenewablesPct2050');
    end
    if ~ismember("Cap2050_Battery", string(KPI.Properties.VariableNames))
        error('Missing KPI column: Cap2050_Battery');
    end

    % Keep finite RE rows and sort by %RE 2050 (same X order logic as your other plots)
    m = isfinite(KPI.RenewablesPct2050);
    K = KPI(m, :);

    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx, :);

    % Battery to GWh (4-hour model)
    battMW  = K.Cap2050_Battery(:);
    battMW(~isfinite(battMW)) = 0;
    battGWh = battMW * 4 / 1000;

    % Color
    battColor = [0.30 0.65 0.40]; % fallback
    if nargin >= 2 && isstruct(colorsBase) && isfield(colorsBase,'Batt') && numel(colorsBase.Batt) == 3
        battColor = colorsBase.Batt;
    end

    % Plot
    fig = figure('Color','w','Position',[220 160 1250 720]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    bar(ax, 1:numel(battGWh), battGWh, ...
        'FaceColor', battColor, ...
        'EdgeColor', 'none', ...
        'BarWidth', 0.75);

    ylabel(ax, 'Battery energy capacity in 2050 [GWh]', 'FontWeight','bold');
    xlabel(ax, 'Scenarios (sorted by %RE 2050)', 'FontWeight','bold');
    title(ax, 'Battery capacity in 2050 (4-hour model)');

    legend(ax, {'Battery (4h, GWh)'}, 'Location','northoutside', 'Orientation','horizontal');

    ax.XGrid = 'off';
    ax.YGrid = 'on';

    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%.0f');

    % X ticks: keep same rule as the rest of your figures
    if nargin < 4 || isempty(scenKeep)
        % ALL scenarios: show ticks only when %RE changes by >= 0.1%
        if exist('applyReBlockTicks','file') == 2
            applyReBlockTicks(ax, re_sorted, 0.1);
        else
            local_applyReBlockTicks(ax, re_sorted, 0.1);
        end
    else
        % Selected scenarios: show tick for every scenario
        if exist('applyReAllScenarioTicks','file') == 2
            applyReAllScenarioTicks(ax, re_sorted);
        else
            local_applyReAllScenarioTicks(ax, re_sorted);
        end
    end
end

% ---- Local fallbacks (only used if your existing helpers are not in scope) ----

function local_applyReAllScenarioTicks(ax, re_sorted)
    n = numel(re_sorted);
    xticks(ax, 1:n);
    xticklabels(ax, arrayfun(@(v) sprintf('%.2f%%', v), re_sorted, 'UniformOutput', false));
    if n <= 40
        xtickangle(ax, 45);
    else
        xtickangle(ax, 90);
        ax.FontSize = max(8, ax.FontSize - 2);
    end
end

function local_applyReBlockTicks(ax, re_sorted, deltaPct)
    n = numel(re_sorted);
    if n == 0
        return;
    end

    tickIdx = 1;
    tickVal = re_sorted(1);
    lastVal = re_sorted(1);

    for i = 2:n
        if (re_sorted(i) - lastVal) >= deltaPct
            tickIdx(end+1,1) = i; %#ok<AGROW>
            tickVal(end+1,1) = re_sorted(i); %#ok<AGROW>
            lastVal = re_sorted(i);
        end
    end

    xticks(ax, tickIdx);
    xticklabels(ax, arrayfun(@(v) sprintf('%.1f%%', v), tickVal, 'UniformOutput', false));
    xtickangle(ax, 45);
end



function T = EXPORT_BATTERY_DISCHARGE_TIME_2050_CSV(KPI, scenRoot, scenKeep, outCsv)
% EXPORT_BATTERY_DISCHARGE_TIME_2050_CSV
% For each selected scenario, compute how long it takes (average/median/max) for the battery
% to go from "full" to "empty" in year 2050, based on the battery energy state time series.
%
% Outputs a CSV and prints a readable summary to the Command Window.
%
% Table columns:
%   - Avg discharge time [hours], [days]
%   - Median discharge time [hours], [days]
%   - Max discharge time [hours], [days]
%   - Max event start/end timestamps (datetime) within 2050
%   - Number of full->empty events detected in 2050
%
% Assumptions:
%   - 1 timestep = 1 hour
%   - Battery is a 4-hour model: Emax_2050_MWh = Cap2050_Battery(MW) * 4
%   - Battery energy state is stored in RES.E (preferred). If missing, tries common fallbacks.
%
% Usage example:
%   outCsv = fullfile(figDir, 'BatteryDischargeTime2050_Selected.csv');
%   T = EXPORT_BATTERY_DISCHARGE_TIME_2050_CSV(KPI, scenRoot, scenKeepB, outCsv);

    if nargin < 4 || isempty(outCsv)
        outCsv = fullfile(pwd, 'BatteryDischargeTime2050_Selected.csv');
    end

     KPI.Scenario = string(KPI.Scenario);


    scenKeep = string(scenKeep(:));
    KPI = KPI(ismember(KPI.Scenario, scenKeep), :);

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder: %s', scenRoot);
    end

    % Required KPI columns (for Emax and convenience fields)
    vn = string(KPI.Properties.VariableNames);
    if ~ismember("Cap2050_Battery", vn)
        error('KPI must contain Cap2050_Battery [MW].');
    end
    hasRE = ismember("RenewablesPct2050", vn);

    % Thresholds to define "full" and "empty"
    FULL_FRAC  = 0.99;
    EMPTY_FRAC = 0.01;

    yearLen = 8760;

    % Prepare output arrays
    n = height(KPI);
    Scenario = KPI.Scenario;

    RE2050 = nan(n,1);
    if hasRE
        RE2050 = KPI.RenewablesPct2050;
    end

    CapBatt2050_MW = KPI.Cap2050_Battery;
    BattEnergy2050_GWh = (CapBatt2050_MW * 4) / 1000;

    NumEvents2050 = zeros(n,1);

    Avg_h   = nan(n,1);
    Med_h   = nan(n,1);
    Max_h   = nan(n,1);

    Avg_day = nan(n,1);
    Med_day = nan(n,1);
    Max_day = nan(n,1);

    MaxEventStart = NaT(n,1);
    MaxEventEnd   = NaT(n,1);

    Notes = strings(n,1);

    for i = 1:n
        scName  = Scenario(i);
        resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
        if ~isfile(resFile)
            Notes(i) = "Missing results_heavy.mat";
            continue;
        end

        S = load(resFile, 'RES');
        if ~isfield(S,'RES') || ~isstruct(S.RES)
            Notes(i) = "Missing/invalid RES struct";
            continue;
        end
        RES = S.RES;

        if ~isfield(RES,'BaseYear') || ~isfinite(RES.BaseYear)
            Notes(i) = "Missing RES.BaseYear";
            continue;
        end

        % Extract battery energy state time series (MWh)
        [E_all, noteE] = local_getBatteryEnergySeries(RES);
        if isempty(E_all)
            Notes(i) = "No battery energy series found (" + noteE + ")";
            continue;
        end
        E_all = E_all(:);

        % Indices for year 2050 within the hourly series
        baseYear = RES.BaseYear;
        y2050Offset = 2050 - baseYear;
        tStartAbs = y2050Offset * yearLen + 1;
        tEndAbs   = tStartAbs + yearLen - 1;

        if tStartAbs < 1 || tEndAbs > numel(E_all)
            Notes(i) = "2050 range out of bounds for E series";
            continue;
        end

        E = E_all(tStartAbs:tEndAbs);

        % Determine Emax_2050 (MWh) using KPI's 4h model
        Emax_MWh = CapBatt2050_MW(i) * 4;
        if ~isfinite(Emax_MWh) || Emax_MWh <= 0
            % Fallback: infer from series if KPI value is not usable
            Emax_MWh = max(E(isfinite(E)));
        end
        if ~isfinite(Emax_MWh) || Emax_MWh <= 0
            Notes(i) = "Emax invalid (battery capacity is zero or series invalid)";
            continue;
        end

        fullThr  = FULL_FRAC  * Emax_MWh;
        emptyThr = EMPTY_FRAC * Emax_MWh;

        % Clean NaNs
        E(~isfinite(E)) = NaN;

        % Detect full->empty events (durations + start/end indices within the 2050 slice)
        [durs_h, startIdx2050, endIdx2050] = local_fullToEmptyDurations(E, fullThr, emptyThr);

        NumEvents2050(i) = numel(durs_h);

        if isempty(durs_h)
            Notes(i) = "No full-to-empty events found in 2050";
            continue;
        end

        Avg_h(i)   = mean(durs_h);
        Med_h(i)   = median(durs_h);
        Max_h(i)   = max(durs_h);

        Avg_day(i) = Avg_h(i) / 24;
        Med_day(i) = Med_h(i) / 24;
        Max_day(i) = Max_h(i) / 24;

        % Identify max event and convert to datetimes
        [~, imax] = max(durs_h);
        s2050 = startIdx2050(imax); % 1..8760 index inside 2050 slice
        e2050 = endIdx2050(imax);

        % Absolute indices in the full hourly series
        sAbs = tStartAbs + (s2050 - 1);
        eAbs = tStartAbs + (e2050 - 1);

        % Convert absolute indices to datetime, assuming hourly steps and BaseYear starts at Jan 1 00:00
        dt0 = datetime(baseYear, 1, 1, 0, 0, 0);
        MaxEventStart(i) = dt0 + hours(sAbs - 1);
        MaxEventEnd(i)   = dt0 + hours(eAbs - 1);

        if strlength(noteE) > 0
            Notes(i) = "E source: " + noteE;
        else
            Notes(i) = "OK";
        end
    end

    % Build output table
    T = table( ...
        Scenario, ...
        RE2050, ...
        CapBatt2050_MW, ...
        BattEnergy2050_GWh, ...
        NumEvents2050, ...
        Avg_h, Avg_day, ...
        Med_h, Med_day, ...
        Max_h, Max_day, ...
        MaxEventStart, MaxEventEnd, ...
        Notes);

    % Write CSV
    try
        writetable(T, outCsv);
        fprintf('Battery discharge time CSV saved to:\n  %s\n', outCsv);
    catch ME
        warning('Failed to write CSV: %s', char(ME.message));
    end

    % Print summary to Command Window
    local_printSummary(T, hasRE);
end

% ---------------- Local helpers ----------------

function [E, note] = local_getBatteryEnergySeries(RES)
% Try to locate a battery energy state series in common field names.
% Returns E as a numeric vector in MWh (expected) and a note string.

    note = "";
    E = [];

    candidates = { ...
        'E', ...
        'Ebatt', ...
        'E_batt', ...
        'BatteryEnergy', ...
        'BattEnergy', ...
        'BatteryLevel', ...
        'BattLevel', ...
        'SOC', ...
        'SoC' ...
    };

    for k = 1:numel(candidates)
        fn = candidates{k};
        if isfield(RES, fn) && ~isempty(RES.(fn)) && isnumeric(RES.(fn))
            E = RES.(fn);
            note = string(fn);
            return;
        end
    end

    note = "no known field";
end

function [durs_h, startIdx, endIdx] = local_fullToEmptyDurations(E, fullThr, emptyThr)
% Scan 1-year hourly series E and find durations (hours) from entering FULL to reaching EMPTY.
% "Entering full" is defined as transition from not-full to full (E >= fullThr).
% After reaching empty, scanning resumes after that point (non-overlapping events).
%
% Outputs:
%   durs_h   - durations in hours
%   startIdx - start indices (1..n) inside the provided E vector
%   endIdx   - end indices (1..n) inside the provided E vector

    n = numel(E);
    durs_h = [];
    startIdx = [];
    endIdx = [];

    isFull  = (E >= fullThr);
    isEmpty = (E <= emptyThr);

    % Ignore NaNs
    isFull(isnan(E))  = false;
    isEmpty(isnan(E)) = false;

    t = 1;
    while t <= n
        % Find next "enter full" event
        if t == 1
            enterFull = isFull(t);
        else
            enterFull = isFull(t) && ~isFull(t-1);
        end

        if ~enterFull
            t = t + 1;
            continue;
        end

        tFull = t;

        % Find first empty after tFull
        rel = find(isEmpty((tFull+1):end), 1, 'first');
        if isempty(rel)
            break;
        end

        tEmpty = tFull + rel;

        dur = tEmpty - tFull; % hours
        if isfinite(dur) && dur > 0
            durs_h(end+1,1)   = dur; %#ok<AGROW>
            startIdx(end+1,1) = tFull; %#ok<AGROW>
            endIdx(end+1,1)   = tEmpty; %#ok<AGROW>
        end

        % Continue scanning after the empty point
        t = tEmpty + 1;
    end
end

function local_printSummary(T, hasRE)
% Print a readable scenario-by-scenario summary to the Command Window.

    fprintf('\n============================================================\n');
    fprintf('Battery full-to-empty discharge time - Year 2050\n');
    fprintf('============================================================\n');

    for i = 1:height(T)
        fprintf('Scenario: %s\n', string(T.Scenario(i)));

        if hasRE && isfinite(T.RE2050(i))
            fprintf('RE 2050: %.2f %%\n', T.RE2050(i));
        end

        if isfinite(T.BattEnergy2050_GWh(i))
            fprintf('Battery capacity: %.3f GWh\n', T.BattEnergy2050_GWh(i));
        end

        fprintf('Events detected: %d\n', T.NumEvents2050(i));

        if isfinite(T.Avg_h(i))
            fprintf('Average discharge time: %.2f h (%.2f days)\n', T.Avg_h(i), T.Avg_day(i));
            fprintf('Median  discharge time: %.2f h (%.2f days)\n', T.Med_h(i), T.Med_day(i));
            fprintf('Max     discharge time: %.2f h (%.2f days)\n', T.Max_h(i), T.Max_day(i));

            if ~isnat(T.MaxEventStart(i)) && ~isnat(T.MaxEventEnd(i))
                fprintf('Max event window: %s  to  %s\n', ...
                    char(T.MaxEventStart(i)), char(T.MaxEventEnd(i)));
            end
        else
            fprintf('No valid full-to-empty events detected\n');
        end

        if strlength(string(T.Notes(i))) > 0
            fprintf('Note: %s\n', string(T.Notes(i)));
        end

        fprintf('------------------------------------------------------------\n');
    end
end


function fig = PLOT_BATTERY_ENERGY_2050_TIMESERIES_SELECTED(KPI, scenRoot, scenKeepB, colorsBase)
% PLOT_BATTERY_ENERGY_2050_TIMESERIES_SELECTED
% Plot battery energy time series over year 2050 for ONE scenario selected from scenKeepB:
% - Choose the FIRST selected scenario with RenewablesPct2050 > 90, after sorting scenKeepB by %RE.
% - Plot battery energy (state) across all 8760 hours of 2050.
% - Legend includes battery capacity in GWh (4-hour model): Cap2050_Battery[MW] * 4 / 1000.
%
% Inputs:
%   KPI        - table including columns: Scenario, RenewablesPct2050, Cap2050_Battery
%   scenRoot   - root folder that contains scenario folders, each with results_heavy.mat
%   scenKeepB  - selected scenarios (string/cellstr)
%   colorsBase - struct with optional field colorsBase.Batt
%
% Output:
%   fig - figure handle

    if nargin < 4
        colorsBase = struct();
    end

     KPI.Scenario = string(KPI.Scenario);


    scenKeepB = string(scenKeepB(:));

    if ~isfolder(scenRoot)
        error('scenRoot is not a valid folder: %s', scenRoot);
    end

    % Required KPI columns
    vn = string(KPI.Properties.VariableNames);
    if ~ismember("Scenario", vn)
        error('KPI must contain "Scenario" column.');
    end
    if ~ismember("RenewablesPct2050", vn)
        error('KPI must contain "RenewablesPct2050" column.');
    end
    if ~ismember("Cap2050_Battery", vn)
        error('KPI must contain "Cap2050_Battery" column (MW).');
    end

    % Filter to selected scenarios
    K = KPI(ismember(KPI.Scenario, scenKeepB), :);
    if isempty(K)
        error('No scenarios in KPI match scenKeepB.');
    end

    % Sort by %RE (ascending)
    m = isfinite(K.RenewablesPct2050);
    K = K(m,:);
    [re_sorted, idx] = sort(K.RenewablesPct2050, 'ascend');
    K = K(idx,:);

    % Pick FIRST scenario with RE > 90
    thr = 90;
    pick = find(re_sorted > thr, 1, 'first');
    if isempty(pick)
        error('No selected scenario has RenewablesPct2050 > %.1f', thr);
    end

    scName = string(K.Scenario(pick));
    reVal  = K.RenewablesPct2050(pick);

    % Battery capacity in GWh (4-hour model)
    capBatt_MW = K.Cap2050_Battery(pick);
    if ~isfinite(capBatt_MW); capBatt_MW = 0; end
    capBatt_GWh = (capBatt_MW * 4) / 1000;

    % Load results
    resFile = fullfile(scenRoot, scName, 'results_heavy.mat');
    if ~isfile(resFile)
        error('Missing results_heavy.mat for scenario: %s', scName);
    end

    S = load(resFile, 'RES');
    if ~isfield(S,'RES') || ~isstruct(S.RES)
        error('Invalid RES struct in %s', resFile);
    end
    RES = S.RES;

    if ~isfield(RES,'BaseYear') || ~isfinite(RES.BaseYear)
        error('RES.BaseYear missing/invalid for scenario: %s', scName);
    end

    % Get battery energy series (MWh)
    [E_all, noteE] = local_getBatteryEnergySeries(RES);
    if isempty(E_all)
        error('No battery energy series found for %s (%s).', scName, noteE);
    end
    E_all = E_all(:);

    % Slice year 2050
    yearLen = 8760;
    baseYear = RES.BaseYear;
    y2050Offset = 2050 - baseYear;

    tStartAbs = y2050Offset * yearLen + 1;
    tEndAbs   = tStartAbs + yearLen - 1;

    if tStartAbs < 1 || tEndAbs > numel(E_all)
        error('2050 range out of bounds for battery energy series in %s.', scName);
    end

    E2050_MWh = E_all(tStartAbs:tEndAbs);
    E2050_MWh(~isfinite(E2050_MWh)) = NaN;

    % Time axis for 2050 (hourly)
    dt0 = datetime(2050, 1, 1, 0, 0, 0);
    dt  = dt0 + hours((0:yearLen-1)');

    % Convert to GWh for plotting
    E2050_GWh = E2050_MWh / 1000;

    % Color
    battColor = [0.30 0.65 0.40];
    if isstruct(colorsBase) && isfield(colorsBase,'Batt') && numel(colorsBase.Batt) == 3
        battColor = colorsBase.Batt;
    end

    % Plot
    fig = figure('Color','w','Position',[220 160 1250 650]);
    ax = axes(fig); hold(ax,'on'); box(ax,'on'); grid(ax,'on');

    plot(ax, dt, E2050_GWh, '-', 'LineWidth', 1.0, 'Color', battColor);

    xlabel(ax, 'Date (2050)', 'FontWeight','bold');
    ylabel(ax, 'Battery energy [GWh]', 'FontWeight','bold');

    title(ax, sprintf('Battery energy in 2050 - %s (RE=%.2f%%)', scName, reVal));

    legTxt = sprintf('Battery energy (Capacity: %.2f GWh)', capBatt_GWh);
    legend(ax, {legTxt}, 'Location','northoutside', 'Orientation','horizontal');

    ax.YAxis.Exponent = 0;
    ytickformat(ax, '%.1f');

    % Optional: keep x-axis readable
    ax.XAxis.TickLabelRotation = 0;

    % Print to command window for traceability
    fprintf('\nBattery 2050 time-series plot:\n');
    fprintf('  Scenario: %s\n', scName);
    fprintf('  RE 2050: %.3f %%\n', reVal);
    fprintf('  Battery capacity (4h): %.3f GWh\n', capBatt_GWh);
    fprintf('  E series source: %s\n', noteE);
end

function localApplyReTargetsTicks(ax, keptRE, reTargets)
% localApplyReTargetsTicks
% Set X-axis tick positions/labels based on representative %RE values,
% while preventing overlaps near the edges.
%
% Inputs:
%   ax       - axes handle
%   keptRE   - vector (n x 1) of %RE values sorted in the same order as bars
%   reTargets- vector of representative %RE targets (can be empty)
%
% Behavior:
% - Always keeps first and last scenario as ticks.
% - Adds nearest indices to each reTarget.
% - Ensures at least ~12 ticks total (including edges) by adding evenly spaced ticks.
% - Removes ticks that are too close in index-space (to avoid label collisions),
%   but never drops the first/last tick.
% - Uses 1-decimal labels.

    if nargin < 3
        reTargets = [];
    end

    keptRE = keptRE(:);
    n = numel(keptRE);
    if n == 0 || ~ishandle(ax)
        return;
    end

    % Edge case: very small n
    if n <= 3
        idxTicks = (1:n).';
        xticks(ax, idxTicks);
        xticklabels(ax, compose('%.1f', keptRE(idxTicks)));
        return;
    end

    % -----------------------------
    % 1) Always keep edges
    % -----------------------------
    idxEdges = [1; n];

    % -----------------------------
    % 2) Add target-based indices
    % -----------------------------
    idxFromTargets = [];
    if ~isempty(reTargets)
        reTargets = reTargets(:);
        idxFromTargets = zeros(numel(reTargets), 1);
        for k = 1:numel(reTargets)
            [~, idxFromTargets(k)] = min(abs(keptRE - reTargets(k)));
        end
    end

    % -----------------------------
    % 3) Ensure a minimum number of ticks (including edges)
    % -----------------------------
    MIN_TICKS_TOTAL = 12; % you can bump to 14 if you want denser labels
    if n < MIN_TICKS_TOTAL
        MIN_TICKS_TOTAL = n;
    end

    idxEven = unique(round(linspace(1, n, MIN_TICKS_TOTAL))).';
    idxTicks = unique([idxEdges; idxFromTargets; idxEven]);

    % -----------------------------
    % 4) De-collide near edges (and anywhere) by enforcing index gap
    % -----------------------------
    idxTicks = sort(idxTicks);

    % Minimal distance (in scenario index units) between tick labels.
    % Increase to 4-5 if you still see collisions.
    minGap = 3;

    % Keep-first-pass: greedy removal of too-close ticks
    keep = true(size(idxTicks));
    for i = 2:numel(idxTicks)
        if idxTicks(i) - idxTicks(i-1) < minGap
            keep(i) = false;
        end
    end
    idxTicks = idxTicks(keep);

    % Ensure edges are still present
    idxTicks = unique([idxTicks; idxEdges]);
    idxTicks = sort(idxTicks);

    % Second pass, but NEVER drop edges:
    if numel(idxTicks) >= 3
        keep = true(size(idxTicks));
        for i = 2:numel(idxTicks)-1
            if idxTicks(i) - idxTicks(i-1) < minGap
                keep(i) = false; % drop the middle one (not edges)
            end
        end
        idxTicks = idxTicks(keep);
        idxTicks = unique([idxTicks; idxEdges]);
        idxTicks = sort(idxTicks);
    end
    % -----------------------------
    % 4.5) Remove duplicate labels (same %RE after rounding shown on axis)
    % -----------------------------
    labelVals = round(keptRE(idxTicks), 1);  % must match the label precision (%.1f)
    
    % Keep unique labels while preserving order
    [~, ia] = unique(labelVals, 'stable');
    idxUnique = idxTicks(ia);
    
    % Always keep edges (even if duplicate due to rounding)
    idxEdges = [1; n];
    idxTicks = unique([idxUnique; idxEdges]);
    idxTicks = sort(idxTicks);
    % -----------------------------
    % 5) Apply to axes
    % -----------------------------
    xticks(ax, idxTicks);
    xticklabels(ax, compose('%.1f', keptRE(idxTicks)));

    % Optional: if you still get collisions, uncomment one of these:
    % xtickangle(ax, 20);
    % xtickangle(ax, 30);

    set(ax, 'TickLabelInterpreter', 'none');
end

function [figLine, figStack, scNameUsed] = UI_PLOT_CAPACITY_GROWTH_STEPS_FROM_RESULTS_HEAVY(scenRoot, scPlot, colorsBase, startYr)
% UI_PLOT_CAPACITY_GROWTH_STEPS_FROM_RESULTS_HEAVY
% Plots installed capacity growth as step changes across the full horizon (e.g., 2023-2050).
% Produces:
%   (A) Line/stairs plot for all sources
%   (C) Stacked "step area" plot (clean, based only on capacity change breakpoints)
%
% Scenario selection:
%   - If scPlot is provided (scenario folder name), loads scenRoot/scPlot/results_heavy.mat
%   - If scPlot is empty or missing, opens a UI file picker (uigetfile) to select results_heavy.mat
%
% Notes:
%   - This implementation avoids plotting hourly stacked areas directly, which can look noisy.
%   - Instead, it compresses the timeline to change points only (breakpoints) and uses a step-expanded
%     time series for a clean stacked step visualization.

    if nargin < 1 || isempty(scenRoot)
        scenRoot = '';
    end
    if nargin < 2
        scPlot = '';
    end
    if nargin < 3 || isempty(colorsBase)
        colorsBase = struct();
    end
    if nargin < 4 || isempty(startYr)
        startYr = 2023;
    end

    % Fallback colors (if missing)
    if ~isfield(colorsBase,'Nuclear'), colorsBase.Nuclear = [0.25 0.35 0.60]; end
    if ~isfield(colorsBase,'Solar'),   colorsBase.Solar   = [0.90 0.75 0.25]; end
    if ~isfield(colorsBase,'Gas'),     colorsBase.Gas     = [0.75 0.25 0.25]; end
    if ~isfield(colorsBase,'Coal'),    colorsBase.Coal    = [0.55 0.35 0.65]; end
    if ~isfield(colorsBase,'Batt'),    colorsBase.Batt    = [0.30 0.65 0.40]; end

    % ---------------------------------------------------------------------
    % Resolve results_heavy.mat path (UI pick if needed)
    % ---------------------------------------------------------------------
    resFile = '';
    scNameUsed = "";

    if nargin >= 2 && ~isempty(scPlot)
        resFile = fullfile(scenRoot, char(scPlot), 'results_heavy.mat');
        if ~isfile(resFile)
            error('results_heavy.mat not found at: %s', resFile);
        end
        scNameUsed = string(scPlot);
    else
        [fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'; '*.*','All files (*.*)'}, ...
            'Select results_heavy.mat file');
        if isequal(fn,0)
            warning('No results_heavy selected. Skipping capacity growth plots.');
            figLine = [];
            figStack = [];
            return;
        end
        resFile = fullfile(fp, fn);

        % Try to infer scenario folder name from path
        % ...\scenarios\<SC_NAME>\results_heavy.mat
        parts = split(string(resFile), filesep);
        if numel(parts) >= 2
            scNameUsed = parts(end-1);
        else
            scNameUsed = "SelectedScenario";
        end
    end

    % ---------------------------------------------------------------------
    % Load RES and extract installed capacity time series K(t)
    % ---------------------------------------------------------------------
    S = load(resFile, 'RES');
    if ~isfield(S,'RES') || ~isstruct(S.RES)
        error('Selected MAT does not contain RES struct.');
    end
    RES = S.RES;

    % Prefer RES.K if exists (installed capacity per hour)
    K = [];
    if isfield(RES,'K') && ~isempty(RES.K)
        K = RES.K;
    elseif isfield(RES,'Kcap') && ~isempty(RES.Kcap)
        K = RES.Kcap;
    elseif isfield(RES,'Cap') && ~isempty(RES.Cap)
        K = RES.Cap;
    else
        error('Could not find installed capacity time series. Expected RES.K (or RES.Kcap / RES.Cap).');
    end

    % Ensure K is [nSrc x T]
    if size(K,1) > size(K,2)
        % Could already be [nSrc x T], keep
    else
        % If it looks like [T x nSrc], transpose
        if size(K,1) == size(RES.U,2) && size(K,2) == size(RES.U,1)
            K = K.';
        end
    end

    nSrc = size(K,1);
    T    = size(K,2);

    % Determine year axis from RES.BaseYear if available
    if isfield(RES,'BaseYear') && isfinite(RES.BaseYear)
        baseYear = RES.BaseYear;
    else
        baseYear = startYr;
    end

    dt0 = datetime(baseYear,1,1,0,0,0);
    dtAll = dt0 + hours(0:T-1);

    % ---------------------------------------------------------------------
    % Define source order and labels (project order)
    % ---------------------------------------------------------------------
    % Expected source order: [Nuclear, Solar, Gas, Coal, Battery]
    % If model has fewer sources, pad/truncate safely.
    srcNames = {'Nuclear','Solar','Gas','Coal','Battery'};
    srcColors = [
        colorsBase.Nuclear
        colorsBase.Solar
        colorsBase.Gas
        colorsBase.Coal
        colorsBase.Batt
    ];

    % Build Kplot as [T x 5] with missing sources as zeros
    Kplot = zeros(T, 5);
    for i = 1:min(nSrc,5)
        Kplot(:,i) = K(i,:).';
    end

    % ---------------------------------------------------------------------
    % Breakpoints: keep only times where any source capacity changes
    % ---------------------------------------------------------------------
    dK = diff(Kplot, 1, 1);                 % (T-1) x 5
    changeMask = any(abs(dK) > 0, 2);        % (T-1) x 1
    changeIdx  = find(changeMask) + 1;       % indices in 1..T
    bp = unique([1; changeIdx; T]);

    dtBP = dtAll(bp);
    KBP  = Kplot(bp,:);                     % nBP x 5

    % Step-expand for clean stacked area and clean stairs-like look
    [dtStep, KStep] = local_step_expand(dtBP, KBP);

    % ---------------------------------------------------------------------
    % (A) Line/stairs plot - clean, based on breakpoints (not full hourly)
    % ---------------------------------------------------------------------
    figLine = figure('Color','w','Position',[200 120 1250 600]);
    ax1 = axes(figLine); hold(ax1,'on'); box(ax1,'on'); grid(ax1,'on');

    for i = 1:5
        stairs(ax1, dtBP, KBP(:,i), 'LineWidth', 1.6, 'Color', srcColors(i,:));
    end

    title(ax1, sprintf('Installed capacity steps across horizon (Scenario: %s)', scNameUsed), ...
        'Interpreter','none');
    xlabel(ax1, 'Date');
    ylabel(ax1, 'Installed capacity [MW]');
    legend(ax1, srcNames, 'Location','northoutside','Orientation','horizontal');

    ax1.YAxis.Exponent = 0;
    ytickformat(ax1,'%.0f');

    % ---------------------------------------------------------------------
    % (C) Stacked step area plot - clean and readable
    % ---------------------------------------------------------------------
    figStack = figure('Color','w','Position',[200 120 1250 600]);
    ax2 = axes(figStack); hold(ax2,'on'); box(ax2,'on'); grid(ax2,'on');

    hA = area(ax2, dtStep, KStep, 'LineStyle','none');
    for i = 1:numel(hA)
        hA(i).FaceColor = srcColors(i,:);
        hA(i).FaceAlpha = 1.0; % No transparency - avoids muddy overlaps
    end

    title(ax2, sprintf('Installed capacity (stacked step view) across horizon (Scenario: %s)', scNameUsed), ...
        'Interpreter','none');
    xlabel(ax2, 'Date');
    ylabel(ax2, 'Installed capacity [MW]');
    legend(ax2, srcNames, 'Location','northoutside','Orientation','horizontal');

    ax2.YAxis.Exponent = 0;
    ytickformat(ax2,'%.0f');

end

% =====================================================================
% Local helper: step-expand a breakpoint time series (for clean step area)
% =====================================================================
function [xStep, YStep] = local_step_expand(x, Y)
% x: n x 1 datetime (breakpoints)
% Y: n x m values at breakpoints
% Output:
%   xStep: (2n-1) x 1 datetime
%   YStep: (2n-1) x m values, piecewise constant between breakpoints

    n = size(Y,1);
    m = size(Y,2);

    if n < 2
        xStep = x;
        YStep = Y;
        return;
    end

    xStep = repmat(x(1), 2*n-1, 1);
    YStep = zeros(2*n-1, m);

    row = 1;
    for i = 1:(n-1)
        xStep(row)   = x(i);
        YStep(row,:) = Y(i,:);
        row = row + 1;

        xStep(row)   = x(i+1);
        YStep(row,:) = Y(i,:); % hold previous value until next breakpoint
        row = row + 1;
    end

    xStep(end)   = x(end);
    YStep(end,:) = Y(end,:);
end

