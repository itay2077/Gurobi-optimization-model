% ============================================================
%  Itay
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


%%
EXPORT_HOURLY_RESULTS(Demand, startYr)
%%
PLOT_HOURLY_AREA_CHART(Demand, startYr)
%%
PLOT_DAILY_ANNUAL_SUMMARY(Demand, startYr)
%%
PLOT_ANNUAL_CAPACITY(startYr)
%%
PLOT_ANNUAL_DETAILED_COST(startYr)


function EXPORT_HOURLY_RESULTS(Demand, startYr)
% EXPORT_HOURLY_RESULTS
% Exports hourly energy results from results_heavy.mat to an Excel file.
% Comments only in English always!

if nargin < 2 || isempty(startYr)
    startYr = 2023;
end

% Get file from user
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0)
    return;
end

% Load data
S = load(fullfile(fp, fn), 'RES');
RES = S.RES;
U = RES.U;

% Extract battery and dump data safely
ChB  = zeros(size(U,2),1);
Dump = zeros(size(U,2),1);
if isfield(RES,'ChB') && ~isempty(RES.ChB),   ChB  = RES.ChB(:);  end
if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end

% Setup time and align lengths
T = size(U,2);
dt = datetime(startYr,1,1,0,0,0) + seconds(3600 * (0:T-1)');
DemandC = Demand(1:min(T, length(Demand)));
DemandC = DemandC(:);
T = length(DemandC);
U = U(:,1:T); ChB = ChB(1:T); Dump = Dump(1:T); dt = dt(1:T);

% Map sources
nSrc = size(U,1);
U_nuc = zeros(T,1); U_sol = zeros(T,1); U_gas = zeros(T,1); U_coal = zeros(T,1); U_batt = zeros(T,1);
if nSrc >= 1, U_nuc = U(1,:)'; end
if nSrc >= 2, U_sol = U(2,:)'; end
if nSrc >= 3, U_gas = U(3,:)'; end
if nSrc >= 4, U_coal = U(4,:)'; end
if nSrc >= 5, U_batt = U(5,:)'; end

% User prompts for filtering
answerYear = inputdlg({'Enter target year (leave empty for all years):'}, 'Year Selection', [1 50], {num2str(startYr)});
if isempty(answerYear)
    return; 
end

if isempty(answerYear{1})
    yMask = true(T, 1);
    fileSuffix = 'AllYears';
else
    targetYear = str2double(answerYear{1});
    yMask = (year(dt) == targetYear);
    
    answerDays = inputdlg({'Start Day (1-365):', 'End Day (1-365):'}, 'Day Selection', [1 50], {'1', '7'});
    if ~isempty(answerDays) && ~isempty(answerDays{1}) && ~isempty(answerDays{2})
        startDay = str2double(answerDays{1});
        endDay = str2double(answerDays{2});
        doy = day(dt, 'dayofyear');
        yMask = yMask & (doy >= startDay) & (doy <= endDay);
        fileSuffix = sprintf('Year%d_Days%d-%d', targetYear, startDay, endDay);
    else
        fileSuffix = sprintf('Year%d', targetYear);
    end
end

% Create and save table
exportTable = table(dt(yMask), DemandC(yMask), U_nuc(yMask), U_sol(yMask), U_gas(yMask), U_coal(yMask), U_batt(yMask), ChB(yMask), Dump(yMask), ...
    'VariableNames', {'DateTime', 'Demand_MW', 'Nuclear_MW', 'Solar_To_Grid_MW', 'Gas_MW', 'Coal_MW', 'Battery_Discharge_MW', 'Grid_To_Battery_MW', 'Curtailed_Solar_MW'});

[~, baseName, ~] = fileparts(fn);
excelFileName = sprintf('HourlyResults_%s_%s.xlsx', baseName, fileSuffix);
excelFullPath = fullfile(fp, excelFileName);
writetable(exportTable, excelFullPath);
disp(['Successfully exported data to: ', excelFullPath]);

end


function PLOT_HOURLY_AREA_CHART(Demand, startYr, useUI)
% PLOT_HOURLY_AREA_CHART
% Plots the hourly generation mix using an area chart.
%
% Update details:
% - Sources of energy are stacked.
% - 'Battery Charge' (Blue-gray) and 'Solar Wasted' (Gray) are stacked
%   ABOVE the demand line, on top of all energy generated.
% - Comments only in English always!

if nargin < 2 || isempty(startYr), startYr = 2023; end
if nargin < 3 || isempty(useUI), useUI = true; end

% Get file from user
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0), return; end

% Load data
S = load(fullfile(fp, fn), 'RES');
RES = S.RES; U = RES.U;

% Extract battery and dump data safely
ChB = zeros(size(U,2),1); Dump = zeros(size(U,2),1);
if isfield(RES,'ChB') && ~isempty(RES.ChB), ChB = RES.ChB(:); end
if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end

% Setup time and align lengths
T = size(U,2);
dt = datetime(startYr,1,1,0,0,0) + seconds(3600 * (0:T-1)');
DemandC = Demand(1:min(T, length(Demand))); DemandC = DemandC(:);
T = length(DemandC);
U = U(:,1:T); ChB = ChB(1:T); Dump = Dump(1:T); dt = dt(1:T);

% Map sources
nSrc = size(U,1);
U_nuc = zeros(T,1); U_sol = zeros(T,1); U_gas = zeros(T,1); U_coal = zeros(T,1); U_batt = zeros(T,1);
if nSrc >= 1, U_nuc = U(1,:)'; end
if nSrc >= 2, U_sol = U(2,:)'; end
if nSrc >= 3, U_gas = U(3,:)'; end
if nSrc >= 4, U_coal = U(4,:)'; end
if nSrc >= 5, U_batt = U(5,:)'; end
hasNuclear = (nSrc >= 1);

% User prompts for filtering
answerYear = inputdlg({'Enter target year (leave empty for all years):'}, 'Year Selection', [1 50], {num2str(startYr)});
if isempty(answerYear), return; end

chartTitle = 'Generation mix - hourly (All Years)';
if isempty(answerYear{1})
    yMask = true(T,1);
else
    targetYear = str2double(answerYear{1});
    yMask = (year(dt) == targetYear);
    chartTitle = sprintf('Generation mix - hourly (%d)', targetYear);
    
    answerDays = inputdlg({'Start Day (1-365):', 'End Day (1-365):'}, 'Day Selection', [1 50], {'1', '7'});
    if ~isempty(answerDays) && ~isempty(answerDays{1}) && ~isempty(answerDays{2})
        startDay = str2double(answerDays{1});
        endDay = str2double(answerDays{2});
        doy = day(dt, 'dayofyear');
        yMask = yMask & (doy >= startDay) & (doy <= endDay);
        chartTitle = sprintf('Generation mix - hourly (%d, Days %d to %d)', targetYear, startDay, endDay);
    end
end

% Apply filter
dt_f = dt(yMask); Dem_f = DemandC(yMask);
Un_f = U_nuc(yMask); Us_f = U_sol(yMask); Ug_f = U_gas(yMask); Uc_f = U_coal(yMask); Ub_f = U_batt(yMask);
ChB_f = ChB(yMask); Dump_f = Dump(yMask);

% --- Updated Logic for Stacking Order and Colors ---
% The requirement is to stack 'Battery Charge' (Blue-gray)
% and 'Solar Wasted' (Gray) ABOVE the Demand.

if hasNuclear
    Y_area = [Un_f, Ug_f, Uc_f, Us_f, Ub_f, ChB_f, Dump_f];
    legNamesArea = {'Nuclear', 'Gas', 'Coal', 'Solar to Grid', 'Battery Discharge', 'Battery Charge', 'Solar Wasted'};
    cmap = [
        1.00 0.00 0.00 ; % Nuclear: Red
        1.00 0.40 0.70 ; % Gas: Pink
        0.55 0.35 0.65 ; % Coal: Purple
        1.00 1.00 0.00 ; % Solar: Yellow
        0.00 0.00 1.00 ; % Battery Discharge: Blue
        0.40 0.50 0.60 ; % Battery Charge: Blue-Gray (requested)
        0.60 0.60 0.60   % Solar Wasted: Gray (requested)
    ];
else
    Y_area = [Ug_f, Uc_f, Us_f, Ub_f, ChB_f, Dump_f];
    legNamesArea = {'Gas', 'Coal', 'Solar to Grid', 'Battery Discharge', 'Battery Charge', 'Solar Wasted'};
    cmap = [
        1.00 0.40 0.70 ; % Gas: Pink
        0.55 0.35 0.65 ; % Coal: Purple
        1.00 1.00 0.00 ; % Solar: Yellow
        0.00 0.00 1.00 ; % Battery Discharge: Blue
        0.40 0.50 0.60 ; % Battery Charge: Blue-Gray (requested)
        0.60 0.60 0.60   % Solar Wasted: Gray (requested)
    ];
end

% Create figure window
if useUI
    analysisFig = uifigure('Name','Hourly Analysis', 'Position',[200 100 1200 720]);
    tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);
    ax = uiaxes(uitab(tg,'Title','Hourly mix'),'Position',[60 80 1100 580]);
else
    fig = figure('Color','w','Position',[200 100 1200 720]);
    ax = axes(fig);
end

hold(ax,'on'); box(ax,'on'); grid(ax,'on');

% Draw Area Chart (This includes Nuclear/Gas/Solar/Batteries Discharge, and now Charge/Wasted on top)
hArea = area(ax, dt_f, Y_area, 'EdgeColor', 'none');
for k = 1:numel(hArea)
    hArea(k).FaceColor = cmap(k,:);
    hArea(k).FaceAlpha = 0.85; % Slight transparency to blending
end

% Draw Lines
% Remove the blue charge line, as it's now an area above demand.
hDemand = plot(ax, dt_f, Dem_f, 'Color', [1 0.5 0], 'LineWidth', 2.5); % Orange demand line

% Finalize aesthetics
xlabel(ax,'Date'); ylabel(ax,'Energy [MWh]');
title(ax, chartTitle);

% legend now needs to list all the area sources (areas) and then demand (line)
fullLegendNames = [legNamesArea, {'Demand'}];
legend(ax, [hArea, hDemand], fullLegendNames, 'Location','northoutside','Orientation','horizontal');

ax.XAxis.TickLabelRotation = 0; ax.XAxis.TickLabelFormat = 'dd/MM/yyyy';

end


function PLOT_DAILY_ANNUAL_SUMMARY(Demand, startYr, useUI)
% PLOT_DAILY_ANNUAL_SUMMARY
% Processes hourly data, aggregates it into daily sums (365 days), 
% and plots an annual profile of resource usage using STACKED BARS.
%
% Stacking order requested:
% 1. Nuclear (Red)
% 2. Solar to Grid (Yellow)
% 3. Gas (Pink)
% 4. Battery Discharge (Blue)
% - Solar Wasted (Gray) remains stacked on top of all sources.
% - Demand is plotted as a thick Orange line representing daily total MWh.
% - Comments only in English always!

if nargin < 2 || isempty(startYr), startYr = 2023; end
if nargin < 3 || isempty(useUI), useUI = true; end

% Get file from user
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0), return; end

% Load data
S = load(fullfile(fp, fn), 'RES');
RES = S.RES; U = RES.U;

% Extract battery and dump data safely
ChB = zeros(size(U,2),1); Dump = zeros(size(U,2),1);
if isfield(RES,'ChB') && ~isempty(RES.ChB), ChB = RES.ChB(:); end
if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end

% Setup time and align lengths
T = size(U,2);
dt = datetime(startYr,1,1,0,0,0) + seconds(3600 * (0:T-1)');
DemandC = Demand(1:min(T, length(Demand))); DemandC = DemandC(:);
T = length(DemandC);
U = U(:,1:T); ChB = ChB(1:T); Dump = Dump(1:T); dt = dt(1:T);

% Map sources (Hourly)
nSrc = size(U,1);
U_nuc  = zeros(T,1); U_sol  = zeros(T,1); U_gas  = zeros(T,1); U_coal = zeros(T,1); U_batt = zeros(T,1);
if nSrc >= 1, U_nuc  = U(1,:)'; end
if nSrc >= 2, U_sol  = U(2,:)'; end
if nSrc >= 3, U_gas  = U(3,:)'; end
if nSrc >= 4, U_coal = U(4,:)'; end
if nSrc >= 5, U_batt = U(5,:)'; end
hasNuclear = (nSrc >= 1);

% User prompt for year selection
answerYear = inputdlg({'Enter specific year to analyze (e.g., 2050):'}, 'Year Selection', [1 50], {'2050'});
if isempty(answerYear) || isempty(answerYear{1}), return; end
targetYear = str2double(answerYear{1});

% Filter hourly data for the selected year
yMask = (year(dt) == targetYear);
if ~any(yMask)
    error('The selected year %d was not found in the dataset.', targetYear);
end

dt_year    = dt(yMask); 
Dem_year   = DemandC(yMask);
Un_year    = U_nuc(yMask); 
Us_year    = U_sol(yMask); 
Ug_year    = U_gas(yMask); 
Uc_year    = U_coal(yMask); 
Ub_year    = U_batt(yMask);
Dump_year  = Dump(yMask);

% --- Daily Aggregation Logic ---
numHours = length(Un_year);
numDays = floor(numHours / 24);

% Truncate to complete days if necessary
if mod(numHours, 24) ~= 0
    numHours = numDays * 24;
    Dem_year   = Dem_year(1:numHours);
    Un_year    = Un_year(1:numHours);
    Us_year    = Us_year(1:numHours);
    Ug_year    = Ug_year(1:numHours);
    Uc_year    = Uc_year(1:numHours);
    Ub_year    = Ub_year(1:numHours);
    Dump_year  = Dump_year(1:numHours);
    dt_year    = dt_year(1:numHours);
end

% Sum every 24 hours to get daily MWh totals
daily_Demand = sum(reshape(Dem_year, 24, numDays), 1)';
daily_Nuc    = sum(reshape(Un_year, 24, numDays), 1)';
daily_Solar  = sum(reshape(Us_year, 24, numDays), 1)';
daily_Gas    = sum(reshape(Ug_year, 24, numDays), 1)';
daily_Coal   = sum(reshape(Uc_year, 24, numDays), 1)';
daily_Batt   = sum(reshape(Ub_year, 24, numDays), 1)';
daily_Dump   = sum(reshape(Dump_year, 24, numDays), 1)';

% Create daily timeline axis
daily_axis = (1:numDays)';

% --- Build Matrix for Stacked Bar Chart ---
% Order: Nuclear -> Solar -> Gas -> Battery Discharge -> Coal -> Solar Wasted
if hasNuclear
    Y_daily_bar = [daily_Nuc, daily_Solar, daily_Gas, daily_Batt, daily_Coal, daily_Dump];
    legNamesBar = {'Nuclear', 'Solar to Grid', 'Gas', 'Battery Discharge', 'Coal', 'Solar Wasted'};
    cmap = [
        1.00 0.00 0.00 ; % Nuclear: Red
        1.00 1.00 0.00 ; % Solar to Grid: Yellow
        1.00 0.40 0.70 ; % Gas: Pink
        0.00 0.00 1.00 ; % Battery Discharge: Blue
        0.55 0.35 0.65 ; % Coal: Purple
        0.60 0.60 0.60   % Solar Wasted: Gray
    ];
else
    Y_daily_bar = [daily_Solar, daily_Gas, daily_Batt, daily_Coal, daily_Dump];
    legNamesBar = {'Solar to Grid', 'Gas', 'Battery Discharge', 'Coal', 'Solar Wasted'};
    cmap = [
        1.00 1.00 0.00 ; % Solar to Grid: Yellow
        1.00 0.40 0.70 ; % Gas: Pink
        0.00 0.00 1.00 ; % Battery Discharge: Blue
        0.55 0.35 0.65 ; % Coal: Purple
        0.60 0.60 0.60   % Solar Wasted: Gray
    ];
end

% --- Plotting ---
if useUI
    analysisFig = uifigure('Name','Annual Daily Profile Analysis', 'Position',[200 100 1200 720]);
    tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);
    ax = uiaxes(uitab(tg,'Title','Daily Annual Summary'),'Position',[60 80 1100 580]);
else
    fig = figure('Color','w','Position',[200 100 1200 720]);
    ax = axes(fig);
end

hold(ax,'on'); box(ax,'on'); grid(ax,'on');

% Draw daily stacked bar chart instead of area
hBar = bar(ax, daily_axis, Y_daily_bar, 'stacked', 'EdgeColor', 'none', 'BarWidth', 1);
for k = 1:numel(hBar)
    hBar(k).FaceColor = cmap(k,:);
    hBar(k).FaceAlpha = 0.85;
end

% Draw thick Orange line for daily demand
hDemand = plot(ax, daily_axis, daily_Demand, 'Color', [1 0.5 0], 'LineWidth', 2.5);

% Labels and Titles
xlabel(ax, ['Day of Year (', num2str(targetYear), ')']);
ylabel(ax, 'Daily Energy Total [MWh]');
title(ax, sprintf('Day by day resource usage - Annual Summary (%d)', targetYear));

% Setup Legend
fullLegendNames = [legNamesBar, {'Daily Demand'}];
legend(ax, [hBar, hDemand], fullLegendNames, 'Location','northoutside','Orientation','horizontal');

% Adjust X-axis limits to match the number of days
xlim(ax, [1 numDays]);

end

function PLOT_ANNUAL_CAPACITY(startYr, useUI)
% PLOT_ANNUAL_CAPACITY
% Extracts the installed capacity (RES.K) at the end of each year
% and plots the cumulative capacity evolution over the simulation horizon.
% Comments only in English always!

if nargin < 1 || isempty(startYr), startYr = 2023; end
if nargin < 2 || isempty(useUI), useUI = true; end

% Get file from user
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0), return; end

% Load data
S = load(fullfile(fp, fn), 'RES');
RES = S.RES; 

if ~isfield(RES, 'K') || isempty(RES.K)
    error('RES.K (Capacity) is missing in the selected results_heavy.mat.');
end
K = RES.K;

% Setup time horizons
T = size(K,2);
numYears = floor(T / 8760);
years_axis = startYr + (0:numYears-1)';

% Extract end-of-year capacity for each source
idx_eoy = (1:numYears) * 8760;
K_annual = K(:, idx_eoy)'; % Transpose to get matrix of [Years x Sources]

nSrc = size(K, 1);
K_nuc  = zeros(numYears, 1);
K_sol  = zeros(numYears, 1);
K_gas  = zeros(numYears, 1);
K_coal = zeros(numYears, 1);
K_batt = zeros(numYears, 1);

if nSrc >= 1, K_nuc  = K_annual(:, 1); end
if nSrc >= 2, K_sol  = K_annual(:, 2); end
if nSrc >= 3, K_gas  = K_annual(:, 3); end
if nSrc >= 4, K_coal = K_annual(:, 4); end
if nSrc >= 5, K_batt = K_annual(:, 5); end

hasNuclear = (nSrc >= 1);

% --- Build Matrix for Stacked Bar Chart ---
% Stacking order requested previously: Nuclear -> Solar -> Gas -> Battery -> Coal
if hasNuclear
    Y_bar = [K_nuc, K_sol, K_gas, K_batt, K_coal];
    legNamesBar = {'Nuclear', 'Solar', 'Gas', 'Battery Capacity', 'Coal'};
    cmap = [
        1.00 0.00 0.00 ; % Nuclear: Red
        1.00 1.00 0.00 ; % Solar: Yellow
        1.00 0.40 0.70 ; % Gas: Pink
        0.00 0.00 1.00 ; % Battery Capacity: Blue
        0.55 0.35 0.65   % Coal: Purple
    ];
else
    Y_bar = [K_sol, K_gas, K_batt, K_coal];
    legNamesBar = {'Solar', 'Gas', 'Battery Capacity', 'Coal'};
    cmap = [
        1.00 1.00 0.00 ; % Solar: Yellow
        1.00 0.40 0.70 ; % Gas: Pink
        0.00 0.00 1.00 ; % Battery Capacity: Blue
        0.55 0.35 0.65   % Coal: Purple
    ];
end

% --- Plotting ---
if useUI
    analysisFig = uifigure('Name','Capacity Expansion Analysis', 'Position',[200 100 1200 720]);
    tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);
    ax = uiaxes(uitab(tg,'Title','Annual Capacity'),'Position',[60 80 1100 580]);
else
    fig = figure('Color','w','Position',[200 100 1200 720]);
    ax = axes(fig);
end

hold(ax,'on'); box(ax,'on'); grid(ax,'on');

% Draw stacked bar chart for capacities
hBar = bar(ax, years_axis, Y_bar, 'stacked', 'EdgeColor', 'none', 'BarWidth', 0.85);
for k = 1:numel(hBar)
    hBar(k).FaceColor = cmap(k,:);
end

% Labels and Titles
xlabel(ax, 'Year');
ylabel(ax, 'Installed Capacity [MW]');
title(ax, 'Annual Installed Capacity Evolution');

% Setup Legend
legend(ax, legNamesBar, 'Location','northoutside','Orientation','horizontal');

% Adjust X-axis ticks to show every single year clearly
xticks(ax, years_axis);
xtickangle(ax, 45);

end


function PLOT_ANNUAL_DETAILED_COST(startYr, useUI, techNames)
% PLOT_ANNUAL_DETAILED_COST_WITH_EXT
% Plots a stacked bar chart of annual costs per year, broken down by 
% Technology and 3 Expense Types (OPEX, CAPEX, Externalities/Tax).
% Costs are displayed in Billions.
% Comments only in English always!

if nargin < 1 || isempty(startYr), startYr = 2023; end
    if nargin < 2 || isempty(useUI), useUI = true; end
    
    % Get file from user
    [fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
    if isequal(fn,0), return; end
    
    % Load data
    S = load(fullfile(fp, fn), 'RES');
    RES = S.RES; 
    
    % Verify the required fields exist
    if ~isfield(RES, 'opCostYearBySource') || ~isfield(RES, 'buildCostYearBySource') || ~isfield(RES, 'extCostYearBySource')
        error('Required fields (OPEX, CAPEX, or Externalities) are missing in RES.');
    end
    
    if nargin < 1 && isfield(RES, 'meta') && isfield(RES.meta, 'startYr')
        startYr = RES.meta.startYr;
    end
    
    % Convert costs to Billions for a cleaner Y-axis
    opex  = RES.opCostYearBySource / 1e9;    % [n_sources x nYears]
    capex = RES.buildCostYearBySource / 1e9; % [n_sources x nYears]
    
    % Sum the externalities across all sources to get a single annual total
    total_ext = sum(RES.extCostYearBySource, 1) / 1e9; % [1 x nYears]
    
    [n_sources, numYears] = size(opex);
    years_axis = startYr + (0:numYears-1)';
    
    % Default technology names if not provided
    if nargin < 3 || isempty(techNames)
        techNames = cell(1, n_sources);
        for i = 1:n_sources
            if i == 1, techNames{i} = 'Nuclear';
            elseif i == 2, techNames{i} = 'Solar';
            elseif i == 3, techNames{i} = 'Gas';
            elseif i == 4, techNames{i} = 'Coal';
            elseif i == 5, techNames{i} = 'Battery';
            else, techNames{i} = sprintf('Tech %d', i);
            end
        end
    end
    
    % --- Prepare Stacked Data ---
    % We need 2 columns per source (OPEX, CAPEX) + 1 final column for Total Externalities
    total_segments = 2 * n_sources + 1;
    stackedData = zeros(numYears, total_segments);
    legendLabels = cell(1, total_segments);
    
    for i = 1:n_sources
        % Insert OPEX (Base color)
        idx_opex = 2*i - 1;
        stackedData(:, idx_opex) = opex(i, :)';
        legendLabels{idx_opex}   = sprintf('%s (OPEX)', techNames{i});
        
        % Insert CAPEX (Lighter color)
        idx_capex = 2*i;
        stackedData(:, idx_capex) = capex(i, :)';
        legendLabels{idx_capex}   = sprintf('%s (CAPEX)', techNames{i});
    end
    
    % Insert Total Externalities as the last (top) segment
    idx_ext = total_segments;
    stackedData(:, idx_ext) = total_ext';
    legendLabels{idx_ext}   = 'Total Externalities';
    
    % --- Define Colors ---
    baseColors = [
        0.25 0.35 0.65; % Blue (Nuclear)
        0.90 0.75 0.20; % Yellow (Solar)
        0.75 0.25 0.25; % Red (Gas)
        0.55 0.40 0.65; % Purple (Coal)
        0.35 0.65 0.40; % Green (Battery)
    ];
    
    colors = zeros(total_segments, 3);
    for i = 1:n_sources
        if i <= size(baseColors, 1)
            base = baseColors(i, :);
        else
            base = rand(1, 3); % Random fallback
        end
        
        % OPEX gets the solid base color
        colors(2*i - 1, :) = base;
        
        % CAPEX gets a lighter version of the same color
        light_color = min(base + 0.35, 1); 
        colors(2*i, :) = light_color;
    end
    
    % Set the color for Total Externalities to Grey
    colors(idx_ext, :) = [0.45 0.45 0.45]; 
    
    % --- Plotting Configuration ---
    if useUI
        analysisFig = uifigure('Name','Detailed Annual Cost Analysis', 'Position',[200 100 1200 720]);
        tg = uitabgroup(analysisFig,'Position',[10 10 1180 700]);
        ax = uiaxes(uitab(tg,'Title','Detailed Cost'),'Position',[60 80 850 580]);
    else
        fig = figure('Color','w','Position',[200 100 1200 720]);
        ax = axes(fig, 'Position', [0.1 0.1 0.65 0.8]); % Leave room on right for legend
    end
    
    hold(ax,'on'); box(ax,'on'); grid(ax,'on');
    
    % Draw the detailed stacked bar chart
    hBar = bar(ax, years_axis, stackedData, 'stacked', 'EdgeColor', 'none', 'BarWidth', 0.85);
    
    % Apply the mapped colors
    for k = 1:length(hBar)
        hBar(k).FaceColor = colors(k, :);
    end
    
    % Labels and Titles
    xlabel(ax, 'Year', 'FontWeight', 'bold');
    ylabel(ax, 'Annual Cost [Billion NIS]', 'FontWeight', 'bold');
    title(ax, 'Annual System Cost per Year (CAPEX, OPEX & Externalities)', 'FontSize', 14);
    
    % Add Legend outside the plot area
    lgd = legend(ax, legendLabels, 'Location', 'northeastoutside', 'FontSize', 9);
    title(lgd, 'Cost Categories');
    
    % Axis formatting
    xticks(ax, years_axis);
    xtickangle(ax, 45);
    ax.YAxis.Exponent = 0;
    
end
