% ============================================================
%  Result Analysis 
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

%% ---------- LOAD RESULTS MAT FILE ----------
% Get file from user
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0)
    return;
end

% Load data
S = load(fullfile(fp, fn), 'RES');
RES = S.RES;

%% ---------- RUN ANALYSIS ----------
% Call the function with 5% discount rate and the starting year
myCostTable = calculate_discounted_costs_compare(RES, 0.06,0.06);
disp(head(myCostTable, 5));


costTable_base = calculate_discounted_costs_compare(RES, 0.06, 0.06);

price_changes = [0, 0,0, 0, 0];

RES_modified = apply_technology_price_changes(RES, price_changes);

costTable_mod = calculate_discounted_costs_compare(RES_modified, 0.06, 0.06);


plot_economic_dashboard(RES, costTable_base, RES_modified, costTable_mod);

INTERACTIVE_PRODUCTION_DASHBOARD(Demand, startYr, S)

%%

function costTable = calculate_discounted_costs_compare(RES, wacc_rate, interest_rate)
    % Set default rates if not provided
    if nargin < 2 || isempty(wacc_rate), wacc_rate = 0.07; end
    if nargin < 3 || isempty(interest_rate), interest_rate = 0.04; end
    
    % Retrieve the base discount rate used inside the optimization model (usually 6%)
    base_r = 0.06; 
    if isfield(RES, 'P') && isfield(RES.P, 'r')
        base_r = RES.P.r;
    end
    
    nYears_local = length(RES.capexYear);
    t = (0 : nYears_local - 1)';
    
    % Create the base discount factor used by the model
    base_df = 1 ./ ((1 + base_r) .^ t);
    
    % --- CRITICAL FIX: UN-DISCOUNT the model's PV results back to Nominal Annualized (PMT) ---
    capex_annual_nom = RES.capexYear(:) ./ base_df;
    opex_annual_nom  = RES.opexYear(:) ./ base_df;
    
    if isfield(RES, 'ExternalitiesYear')
        ext_annual_nom = RES.ExternalitiesYear(:) ./ base_df;
    else
        ext_annual_nom = zeros(nYears_local, 1);
    end
    
    % Total undiscounted nominal annual costs
    total_annual_nom = capex_annual_nom + opex_annual_nom + ext_annual_nom;
    
    % Safely extract start year
    if isfield(RES, 'startYr')
        start_year = RES.startYr;
    elseif isfield(RES, 'BaseYear')
        start_year = RES.BaseYear;
    else
        start_year = 2023; 
    end
    years = (start_year : start_year + nYears_local - 1)';
    
    % Calculate new discount factors for comparison
    df_wacc = 1 ./ ((1 + wacc_rate) .^ t);
    df_int  = 1 ./ ((1 + interest_rate) .^ t);
    
    % Calculate PV using WACC (on the nominal values!)
    capex_pv_wacc = capex_annual_nom .* df_wacc;
    opex_pv_wacc  = opex_annual_nom .* df_wacc;
    ext_pv_wacc   = ext_annual_nom .* df_wacc;
    total_pv_wacc = total_annual_nom .* df_wacc;
    
    % Calculate PV using Interest rate (on the nominal values!)
    capex_pv_int = capex_annual_nom .* df_int;
    opex_pv_int  = opex_annual_nom .* df_int;
    ext_pv_int   = ext_annual_nom .* df_int;
    total_pv_int = total_annual_nom .* df_int;
    
    % Calculate Cumulative Sums
    total_cumul_undisc = cumsum(total_annual_nom);
    total_cumul_wacc   = cumsum(total_pv_wacc);
    total_cumul_int    = cumsum(total_pv_int);
    
    % Create the table
    costTable = table(years, capex_annual_nom, opex_annual_nom, ext_annual_nom, total_annual_nom, total_cumul_undisc, ...
        df_wacc, capex_pv_wacc, opex_pv_wacc, ext_pv_wacc, total_pv_wacc, total_cumul_wacc, ...
        df_int, capex_pv_int, opex_pv_int, ext_pv_int, total_pv_int, total_cumul_int, ...
        'VariableNames', {'Year', 'CAPEX_Undisc', 'OPEX_Undisc', 'Ext_Undisc', 'Total_Undisc', 'Total_Cumul_Undisc', ...
        'DF_WACC', 'CAPEX_PV_WACC', 'OPEX_PV_WACC', 'Ext_PV_WACC', 'Total_PV_WACC', 'Total_Cumul_WACC', ...
        'DF_Interest', 'CAPEX_PV_Int', 'OPEX_PV_Int', 'Ext_PV_Int', 'Total_PV_Int', 'Total_Cumul_Int'});
        
    % Print summary
    fprintf('\n--- Economic Summary (Based on Nominal Reconstructed PMT) ---\n');
    fprintf('1. Using WACC (%.1f%%):\n', wacc_rate * 100);
    fprintf('   Total CAPEX PV: %15.2f\n', sum(capex_pv_wacc));
    fprintf('   Total NPV:      %15.2f\n\n', total_cumul_wacc(end)); 
    fprintf('2. Using Interest Rate (%.1f%%):\n', interest_rate * 100);
    fprintf('   Total NPV:      %15.2f\n', total_cumul_int(end)); 
    fprintf('------------------------------------------------------\n\n');
end


function RES_new = apply_technology_price_changes(RES, tech_rates)
    % Applies annual price changes (compounding) to specific technologies
    %
    % Inputs:
    % RES - Original model results structure
    % tech_rates - Vector of annual change rates per technology (e.g., [-0.05, 0, 0, 0.2, 0])
    %
    % Output:
    % RES_new - A new results structure with updated costs
    
    % 1. Create a full copy of the original results
    RES_new = RES;
    
    % Ensure tech_rates is a row vector
    tech_rates = tech_rates(:)';
    
    % 2. Validate input vector length
    n_sources = RES.meta.n_sources;
    if length(tech_rates) ~= n_sources
        error('Error: Length of tech_rates (%d) must match RES.meta.n_sources (%d).', length(tech_rates), n_sources);
    end
    
    % 3. Setup time vector for compounding (starting at t=0)
    nYears = length(RES.capexYear);
    t = (0 : nYears - 1)';
    
    % Check matrix orientation (assuming [Years x Sources], transpose if [Sources x Years])
    [rows, cols] = size(RES_new.buildCostYearBySource);
    is_transposed = false;
    if cols ~= n_sources && rows == n_sources
        RES_new.buildCostYearBySource = RES_new.buildCostYearBySource';
        RES_new.opCostYearBySource    = RES_new.opCostYearBySource';
        if isfield(RES_new, 'extCostYearBySource')
            RES_new.extCostYearBySource = RES_new.extCostYearBySource';
        end
        is_transposed = true;
    end
    
    % 4. Apply compounding rate per technology
    for i = 1:n_sources
        % Calculate compound factor for this specific technology
        compound_factor = (1 + tech_rates(i)) .^ t;
        
        % Multiply the source costs by the compound factor
        RES_new.buildCostYearBySource(:, i) = RES_new.buildCostYearBySource(:, i) .* compound_factor;
        RES_new.opCostYearBySource(:, i)    = RES_new.opCostYearBySource(:, i) .* compound_factor;
        
        if isfield(RES_new, 'extCostYearBySource')
            RES_new.extCostYearBySource(:, i) = RES_new.extCostYearBySource(:, i) .* compound_factor;
        end
    end
    
    % 5. Re-aggregate total system costs
    if is_transposed
        % Transpose back to original shape
        RES_new.buildCostYearBySource = RES_new.buildCostYearBySource';
        RES_new.opCostYearBySource    = RES_new.opCostYearBySource';
        RES_new.capexYear = sum(RES_new.buildCostYearBySource, 1)';
        RES_new.opexYear  = sum(RES_new.opCostYearBySource, 1)';
        
        if isfield(RES_new, 'extCostYearBySource')
            RES_new.extCostYearBySource = RES_new.extCostYearBySource';
            RES_new.ExternalitiesYear   = sum(RES_new.extCostYearBySource, 1)';
        end
    else
        % Standard sum across columns (sources)
        RES_new.capexYear = sum(RES_new.buildCostYearBySource, 2);
        RES_new.opexYear  = sum(RES_new.opCostYearBySource, 2);
        
        if isfield(RES_new, 'extCostYearBySource')
            RES_new.ExternalitiesYear = sum(RES_new.extCostYearBySource, 2);
        end
    end
    
    % Update total annual actual cost
    if isfield(RES_new, 'ExternalitiesYear')
        RES_new.totalAnnualCost_actual = RES_new.capexYear + RES_new.opexYear + RES_new.ExternalitiesYear;
    else
        RES_new.totalAnnualCost_actual = RES_new.capexYear + RES_new.opexYear;
    end
    
    fprintf('Technology price changes applied successfully. Total costs re-aggregated.\n');
end




%%charts
function plot_economic_dashboard(RES_base, costTable_base, RES_mod, costTable_mod)
    % Creates a multi-tab interactive dashboard for economic analysis
    %
    % Inputs:
    % RES_base       - Original results structure
    % costTable_base - Output of calculate_discounted_costs_compare for base
    % RES_mod        - Modified results structure (after price changes)
    % costTable_mod  - Output of calculate_discounted_costs_compare for modified
    % tech_names     - (Optional) Cell array of strings with technology names
    
    n_sources = RES_base.meta.n_sources;
    years = costTable_mod.Year;
    tech_names = {'Nuclear', 'Solar', 'Gas', 'Coal', 'Storage'};


    % Create main figure window
    fig = figure('Name', 'Energy System Economic Dashboard', 'NumberTitle', 'off', ...
                 'Position', [100, 100, 1100, 650], 'Color', 'w');
    
    % Create tab group
    tgroup = uitabgroup(fig);
    
    %% Tab 1: Cumulative NPV Comparison (Modified Scenario)
    tab1 = uitab(tgroup, 'Title', '1. Cumulative NPV');
    ax1 = axes('Parent', tab1);
    
    plot(ax1, years, costTable_mod.Total_Cumul_Undisc, '--k', 'LineWidth', 2);
    hold(ax1, 'on');
    plot(ax1, years, costTable_mod.Total_Cumul_WACC, 'LineWidth', 2.5, 'Color', '#0072BD');
    plot(ax1, years, costTable_mod.Total_Cumul_Int, 'LineWidth', 2.5, 'Color', '#D95319');
    
    grid(ax1, 'on');
    title(ax1, 'Cumulative Present Value (NPV) Over Time - Modified Scenario', 'FontSize', 14);
    xlabel(ax1, 'Year', 'FontSize', 12);
    ylabel(ax1, 'Cumulative Cost', 'FontSize', 12);
    legend(ax1, 'Undiscounted Cost (Nominal)', 'Commercial Perspective (WACC)', 'Social Perspective (Interest)', 'Location', 'northwest');
    
    %% Tab 2: Discounted Annual Cost Breakdown (Modified Scenario)
    tab2 = uitab(tgroup, 'Title', '2. Annual Breakdown (WACC)');
    ax2 = axes('Parent', tab2);
    costs_stacked = [costTable_mod.CAPEX_PV_WACC, costTable_mod.OPEX_PV_WACC, costTable_mod.Ext_PV_WACC];
    b2 = bar(ax2, years, costs_stacked, 'stacked');
    grid(ax2, 'on');
    title(ax2, 'Total Discounted Annual Costs Breakdown (WACC)', 'FontSize', 14);
    xlabel(ax2, 'Year', 'FontSize', 12);
    ylabel(ax2, 'Present Value (Discounted)', 'FontSize', 12);
    legend(ax2, {'CAPEX', 'OPEX', 'Externalities'}, 'Location', 'northeast');
    
    % Fix colors for Tab 2
    colors_tab2 = [0.2 0.6 0.8; 0.9 0.7 0.1; 0.8 0.3 0.3];
    for k = 1:length(b2)
        b2(k).FaceColor = colors_tab2(k, :);
    end
    
   %% Tab 3: Detailed Tech & Cost Breakdown (Undiscounted) - FIXED COLORS
    tab3 = uitab(tgroup, 'Title', '3. Detailed Tech Breakdown');
    ax3 = axes('Parent', tab3);
    
    has_ext = isfield(RES_mod, 'extCostYearBySource');
    detailed_matrix = [];
    detailed_legend = {};
    custom_colormap = []; 
    
    % Retrieve base discount rate to reconstruct nominal values for the plot
    base_r = 0.06;
    if isfield(RES_mod, 'P') && isfield(RES_mod.P, 'r'), base_r = RES_mod.P.r; end
    base_df_matrix = repmat(1 ./ ((1 + base_r) .^ (0:length(years)-1)'), 1, n_sources);
    
    % Ensure correct orientation and UN-DISCOUNT back to nominal
    build_costs = RES_mod.buildCostYearBySource;
    op_costs = RES_mod.opCostYearBySource;
    if size(build_costs, 1) ~= length(years)
        build_costs = (build_costs') ./ base_df_matrix;
        op_costs = (op_costs') ./ base_df_matrix;
        if has_ext, ext_costs = (RES_mod.extCostYearBySource') ./ base_df_matrix; end
    else
        build_costs = build_costs ./ base_df_matrix;
        op_costs = op_costs ./ base_df_matrix;
        if has_ext, ext_costs = RES_mod.extCostYearBySource ./ base_df_matrix; end
    end
    
    % Build matrix and assign dynamic colors per technology
    for i = 1:n_sources
        t_name = lower(tech_names{i});
        
        if contains(t_name, 'solar') || contains(t_name, 'pv'), base_color = [0.95, 0.85, 0.10];
        elseif contains(t_name, 'gas'), base_color = [0.60, 0.20, 0.80];
        elseif contains(t_name, 'nucle'), base_color = [0.85, 0.15, 0.15];
        elseif contains(t_name, 'coal'), base_color = [0.40, 0.40, 0.40]; 
        elseif contains(t_name, 'stor') || contains(t_name, 'batt'), base_color = [0.15, 0.45, 0.90];
        else, def_colors = lines(n_sources); base_color = def_colors(i, :); end
        
        color_capex = base_color + (1 - base_color) * 0.55; 
        color_opex  = base_color;                           
        color_ext   = base_color * 0.40;                    
        
        % Add vectors
        detailed_matrix = [detailed_matrix, build_costs(:, i)];
        detailed_legend{end+1} = [tech_names{i} ' CAPEX'];
        custom_colormap = [custom_colormap; color_capex];
        
        detailed_matrix = [detailed_matrix, op_costs(:, i)];
        detailed_legend{end+1} = [tech_names{i} ' OPEX'];
        custom_colormap = [custom_colormap; color_opex];
        
        if has_ext
            detailed_matrix = [detailed_matrix, ext_costs(:, i)];
            detailed_legend{end+1} = [tech_names{i} ' Ext'];
            custom_colormap = [custom_colormap; color_ext];
        end
    end
    
    b3 = bar(ax3, years, detailed_matrix, 'stacked', 'EdgeColor', 'none');
    for k = 1:length(b3)
        b3(k).FaceColor = custom_colormap(k, :);
    end
    
    grid(ax3, 'on');
    title(ax3, 'Annual Costs Breakdown by Technology and Type (Nominal Annualized)', 'FontSize', 14);
    xlabel(ax3, 'Year', 'FontSize', 12);
    ylabel(ax3, 'Total Cost (Undiscounted)', 'FontSize', 12);
    legend(ax3, detailed_legend, 'Location', 'eastoutside', 'FontSize', 9);

    %% Tab 4: Scenario Comparison (Base vs Modified)
    tab4 = uitab(tgroup, 'Title', '4. Scenario Comparison');
    ax4 = axes('Parent', tab4);
    
    base_totals = [sum(costTable_base.CAPEX_PV_WACC), sum(costTable_base.OPEX_PV_WACC), sum(costTable_base.Ext_PV_WACC)];
    mod_totals  = [sum(costTable_mod.CAPEX_PV_WACC), sum(costTable_mod.OPEX_PV_WACC), sum(costTable_mod.Ext_PV_WACC)];
    
    b4 = bar(ax4, [base_totals; mod_totals], 'stacked');
    set(ax4, 'XTickLabel', {'Base Scenario', 'Modified Scenario'});
    grid(ax4, 'on');
    title(ax4, 'Total Project NPV Comparison (WACC)', 'FontSize', 14);
    ylabel(ax4, 'Total Present Value', 'FontSize', 12);
    legend(ax4, {'Total CAPEX PV', 'Total OPEX PV', 'Total Ext PV'}, 'Location', 'northwest');
    
   
   % Fix colors for Tab 4 to match Tab 2
    for k = 1:length(b4)
        b4(k).FaceColor = colors_tab2(k, :);
    end
    
    % FIX: Added 'ax4' to direct the text to the correct tab
    text(ax4, 1, sum(base_totals)*1.02, sprintf('%.2e', sum(base_totals)), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
    text(ax4, 2, sum(mod_totals)*1.02, sprintf('%.2e', sum(mod_totals)), 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
   %% Tab 5: LCOE Trend Comparison
    tab5 = uitab(tgroup, 'Title', '5. LCOE Trend');
    ax5 = axes('Parent', tab5);
    
    if isfield(RES_base, 'elecYear')
        energy_vector = RES_base.elecYear(:);
    elseif isfield(RES_base, 'genYear')
        energy_vector = sum(RES_base.genYear, 1)'; % Fixed bug for matrix orientation
    else
        energy_vector = ones(length(years), 1); 
    end
    
    % --- CRITICAL FIX: Discount the energy vector to match PV costs ---
    base_r = 0.06;
    if isfield(RES_base, 'P') && isfield(RES_base.P, 'r'), base_r = RES_base.P.r; end
    t_years = (0 : length(energy_vector) - 1)';
    base_df = 1 ./ ((1 + base_r) .^ t_years);
    
    energy_vector_pv = energy_vector .* base_df;
    
    % Calculate LCOE (PV Cost / PV Energy)
    lcoe_base = RES_base.totalAnnualCost_actual(:) ./ energy_vector_pv;
    lcoe_mod  = RES_mod.totalAnnualCost_actual(:) ./ energy_vector_pv;
    
    plot(ax5, years, lcoe_base, '--', 'LineWidth', 2, 'Color', '#7E2F8E');
    hold(ax5, 'on');
    plot(ax5, years, lcoe_mod, '-', 'LineWidth', 2.5, 'Color', '#77AC30');
    grid(ax5, 'on');
    title(ax5, 'Levelized Cost of Energy (LCOE) Trend Comparison', 'FontSize', 14);
    xlabel(ax5, 'Year', 'FontSize', 12);
    ylabel(ax5, 'Cost per Unit (NIS/MWh)', 'FontSize', 12);
    legend(ax5, 'Base Scenario', 'Modified Scenario', 'Location', 'northwest');
end

function INTERACTIVE_PRODUCTION_DASHBOARD(Demand, startYr, S)
% INTERACTIVE_PRODUCTION_DASHBOARD
% Creates a 3-level interactive dashboard (Yearly -> Daily -> Hourly).
% Clicking on a year updates the daily view.
% Clicking on a day updates the hourly view.
%
% Comments only in English always!

    if nargin < 2 || isempty(startYr), startYr = 2023; end
    if nargin < 1 || isempty(Demand)
        error('Demand vector is required as the first argument.');
    end

    % 1. Get file from user OR use provided data structure 'S'
    if nargin < 3 || isempty(S)
        [fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
        if isequal(fn,0), return; end
        
        S = load(fullfile(fp, fn), 'RES');
    end
    
    % Ensure the structure contains RES
    if ~isfield(S, 'RES')
        error('The provided structure or file does not contain the RES field.');
    end
    
    RES = S.RES; 
    U = RES.U;

    % Extract dump safely
    Dump = zeros(size(U,2), 1);
    if isfield(RES,'Dump') && ~isempty(RES.Dump), Dump = RES.Dump(:); end
    
    % 3. Setup time and align lengths
    T = size(U,2);
    DemandC = Demand(1:min(T, length(Demand))); DemandC = DemandC(:);
    T = length(DemandC);
    
    U = U(:, 1:T);
    Dump = Dump(1:T);
    
    % Calculate complete years (8760 hours per year)
    numYears = floor(T / 8760);
    if numYears < 1
        error('Not enough data for a full year (requires at least 8760 hours).');
    end
    
    % Truncate to whole years
    T_valid = numYears * 8760;
    U = U(:, 1:T_valid);
    Dump = Dump(1:T_valid);
    DemandC = DemandC(1:T_valid);
    
    % Map sources: 1=Nuc, 2=Sol, 3=Gas, 4=Coal, 5=Batt
    nSrc = size(U,1);
    U_nuc = zeros(T_valid,1); U_sol = zeros(T_valid,1); 
    U_gas = zeros(T_valid,1); U_coal = zeros(T_valid,1); U_batt = zeros(T_valid,1);
    
    if nSrc >= 1, U_nuc = U(1,:)'; end
    if nSrc >= 2, U_sol = U(2,:)'; end
    if nSrc >= 3, U_gas = U(3,:)'; end
    if nSrc >= 4, U_coal = U(4,:)'; end
    if nSrc >= 5, U_batt = U(5,:)'; end

    % Define Colors and Legend based on user request
    % Nuc(Red), Sol(Yellow), Gas(Purple), Coal(Gray), Batt(Blue), Dump(Very Light Gray)
    cmap = [
        1.00, 0.00, 0.00; % Nuclear: Red
        1.00, 1.00, 0.00; % Solar: Yellow
        0.50, 0.00, 0.50; % Gas: Purple
        0.50, 0.50, 0.50; % Coal: Gray
        0.00, 0.00, 1.00; % Battery: Blue
        0.90, 0.90, 0.90  % Dump: Very Light Gray
    ];
    legNames = {'Nuclear', 'Solar', 'Gas', 'Coal', 'Battery', 'Solar Wasted'};

    % Create the UI Figure
    fig = uifigure('Name', 'Interactive Production Dashboard', 'Position', [100, 50, 1200, 900]);
    t = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
    
    % Create axes
    axYear = nexttile(t, 1);
    axDay  = nexttile(t, 2);
    axHour = nexttile(t, 3);
    
    % Initialize UI with default selections
    currentYear = startYr;
    currentDay = 1;
    
    % --- Initial Plots ---
    plotYearly();
    plotDaily(currentYear);
    plotHourly(currentYear, currentDay);

    
    % =========================================================================
    % NESTED FUNCTIONS FOR PLOTTING AND INTERACTION
    % =========================================================================
    
    function plotYearly()
        cla(axYear); hold(axYear, 'on'); grid(axYear, 'on');
        
        % Aggregate yearly
        y_Demand = sum(reshape(DemandC, 8760, numYears), 1)';
        y_Nuc    = sum(reshape(U_nuc, 8760, numYears), 1)';
        y_Sol    = sum(reshape(U_sol, 8760, numYears), 1)';
        y_Gas    = sum(reshape(U_gas, 8760, numYears), 1)';
        y_Coal   = sum(reshape(U_coal, 8760, numYears), 1)';
        y_Batt   = sum(reshape(U_batt, 8760, numYears), 1)';
        y_Dump   = sum(reshape(Dump, 8760, numYears), 1)';
        
        Y_bar = [y_Nuc, y_Sol, y_Gas, y_Coal, y_Batt, y_Dump];
        x_years = startYr : (startYr + numYears - 1);
        
        hBar = bar(axYear, x_years, Y_bar, 'stacked', 'EdgeColor', 'none');
        for k = 1:numel(hBar)
            hBar(k).FaceColor = cmap(k,:);
            hBar(k).HitTest = 'off'; % Pass clicks to the axes
        end
        
        hLine = plot(axYear, x_years, y_Demand, 'Color', [1, 0.5, 0], 'LineWidth', 2.5, 'HitTest', 'off');
        
        ylabel(axYear, 'Energy [MWh]');
        title(axYear, 'Yearly Production Summary (Click on a bar to drill-down to days)');
        xticks(axYear, x_years);
        xlim(axYear, [startYr-0.5, startYr + numYears - 0.5]);
        
        % FIX: Let MATLAB map the objects automatically without array concatenation
        legend(axYear, [legNames, {'Demand'}], 'Location', 'northoutside', 'Orientation', 'horizontal');
        
        % Setup click callback
        set(axYear, 'ButtonDownFcn', @yearClicked);
    end

    function plotDaily(yr)
        cla(axDay); hold(axDay, 'on'); grid(axDay, 'on');
        
        % Extract specific year
        y_idx = yr - startYr;
        idx_start = y_idx * 8760 + 1;
        idx_end = (y_idx + 1) * 8760;
        
        d_Demand = sum(reshape(DemandC(idx_start:idx_end), 24, 365), 1)';
        d_Nuc    = sum(reshape(U_nuc(idx_start:idx_end), 24, 365), 1)';
        d_Sol    = sum(reshape(U_sol(idx_start:idx_end), 24, 365), 1)';
        d_Gas    = sum(reshape(U_gas(idx_start:idx_end), 24, 365), 1)';
        d_Coal   = sum(reshape(U_coal(idx_start:idx_end), 24, 365), 1)';
        d_Batt   = sum(reshape(U_batt(idx_start:idx_end), 24, 365), 1)';
        d_Dump   = sum(reshape(Dump(idx_start:idx_end), 24, 365), 1)';
        
        Y_bar = [d_Nuc, d_Sol, d_Gas, d_Coal, d_Batt, d_Dump];
        x_days = 1:365;
        
        hBar = bar(axDay, x_days, Y_bar, 'stacked', 'EdgeColor', 'none', 'BarWidth', 1);
        for k = 1:numel(hBar)
            hBar(k).FaceColor = cmap(k,:);
            hBar(k).HitTest = 'off';
        end
        
        plot(axDay, x_days, d_Demand, 'Color', [1, 0.5, 0], 'LineWidth', 2, 'HitTest', 'off');
        
        ylabel(axDay, 'Energy [MWh]');
        title(axDay, sprintf('Daily Production - Year %d (Click on a bar to drill-down to hours)', yr));
        xlim(axDay, [0.5, 365.5]);
        
        % Setup click callback
        set(axDay, 'ButtonDownFcn', @dayClicked);
    end

    function plotHourly(yr, day)
        cla(axHour); hold(axHour, 'on'); grid(axHour, 'on');
        
        % Extract specific day from specific year
        y_idx = yr - startYr;
        h_start = y_idx * 8760 + (day - 1) * 24 + 1;
        h_end = h_start + 23;
        
        h_Demand = DemandC(h_start:h_end);
        h_Nuc    = U_nuc(h_start:h_end);
        h_Sol    = U_sol(h_start:h_end);
        h_Gas    = U_gas(h_start:h_end);
        h_Coal   = U_coal(h_start:h_end);
        h_Batt   = U_batt(h_start:h_end);
        h_Dump   = Dump(h_start:h_end);
        
        Y_bar = [h_Nuc, h_Sol, h_Gas, h_Coal, h_Batt, h_Dump];
        x_hours = 1:24;
        
        hBar = bar(axHour, x_hours, Y_bar, 'stacked', 'EdgeColor', 'none', 'BarWidth', 1);
        for k = 1:numel(hBar)
            hBar(k).FaceColor = cmap(k,:);
        end
        
        plot(axHour, x_hours, h_Demand, 'Color', [1, 0.5, 0], 'LineWidth', 2);
        
        ylabel(axHour, 'Power [MW]');
        xlabel(axHour, 'Hour of the Day');
        title(axHour, sprintf('Hourly Production - Year %d, Day %d', yr, day));
        xticks(axHour, 1:24);
        xlim(axHour, [0.5, 24.5]);
    end

    % --- CALLBACK FUNCTIONS ---
    
    function yearClicked(~, ~)
        pt = axYear.CurrentPoint;
        clickedX = round(pt(1,1));
        
        % Validate click boundaries
        if clickedX >= startYr && clickedX <= (startYr + numYears - 1)
            currentYear = clickedX;
            currentDay = 1; % Reset day view when year changes
            plotDaily(currentYear);
            plotHourly(currentYear, currentDay);
        end
    end

    function dayClicked(~, ~)
        pt = axDay.CurrentPoint;
        clickedX = round(pt(1,1));
        
        % Validate click boundaries
        if clickedX >= 1 && clickedX <= 365
            currentDay = clickedX;
            plotHourly(currentYear, currentDay);
        end
    end

end