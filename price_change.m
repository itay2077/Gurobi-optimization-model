% Get file from user safely
[fn, fp] = uigetfile({'*.mat','results_heavy MAT (*.mat)'}, 'Select results_heavy.mat file');
if isequal(fn,0), return; end
    
% Load data safely
loadedData = load(fullfile(fp, fn), 'RES');
if ~isfield(loadedData, 'RES')
    error('The selected file does not contain a "RES" variable.');
end
RES = loadedData.RES; 

% Sensitivity parameters
r = [0.5, 0.6 , 0.7 , 0.8, 0.9 , 1 , 1.1, 1.2 , 1.3 , 1.4 , 1.5];
n_sources = RES.P.n_sources; % Extracted safely from the loaded RES

% Preallocate the solutions matrix for algorithmic efficiency
% Dimensions: [number of scenarios x 3 columns]
num_scenarios = length(r) * n_sources;
solutions = zeros(num_scenarios, 3); 

row_idx = 1;

for i = 1:length(r)
    for s = 1:n_sources
        % 1. Reset P_new to the baseline
        P_new = RES.P;
        
        % 2. Apply the multiplier to the specific source 's' using scalar r(i)
        P_new.costU(s) = r(i) * P_new.costU(s); 
        P_new.costZ(s) = r(i) * P_new.costZ(s); 
        
        % 3. Recalculate economics based on the new prices
        RES_tmp = RECALCULATE_ECONOMICS(RES, P_new); 
        
        % 4. Store the result in the preallocated matrix: [Multiplier, Source ID, Total Cost]
        solutions(row_idx, :) = [r(i), s, RES_tmp.TotalCost_AllYears];
        
        % Advance the matrix row index
        row_idx = row_idx + 1;
    end       
end

% Now 'solutions' is a clean mathematical matrix you can use for plotting
PLOT_SENSITIVITY_ANALYSIS(solutions)

function RES_new = RECALCULATE_ECONOMICS(RES, P)
% RECALCULATE_ECONOMICS
% Performs sensitivity analysis by recalculating all financial KPIs 
% (OPEX, CAPEX, Externalities, LCOE) for an existing physical solution (RES)
% using a new set of economic parameters (P).

    % 1. Copy the physical solution
    RES_new = RES;
    
    % 2. Extract fixed physical matrices from RES
    U       = RES.U;
    K       = RES.K;
    Z       = RES.Z;
    ChB     = RES.ChB;
    genYear = RES.genYear; % Already calculated physically
    elecYear= RES.elecYear;
    emitYear= RES.emitYear;
    
    % 3. Extract parameters from P (These are the ones you change!)
    n_sources       = P.n_sources;
    nYears          = P.nYears;
    yearLen         = P.yearLen;
    costZ           = P.costZ;
    costU           = P.costU;
    p_step          = P.p; % Building steps vector
    tau_ch          = P.tau_ch;
    tau_dis         = P.tau_dis;
    cf              = P.cf;
    c               = P.c;
    cSolar_t        = P.cSolar_t;
    cBatt_t         = P.cBatt_t;
    EmissionsFactor = P.EmissionsFactor; % The Carbon Tax
    
    % 4. Pre-allocate financial matrices
    opCostYearBySource    = zeros(n_sources, nYears);
    extCostYearBySource   = zeros(n_sources, nYears);
    buildCostYearBySource = zeros(n_sources, nYears);
    
    % 5. Recalculate annual economics
    for y = 1:nYears
        rng = (y-1)*yearLen + (1:yearLen);
        
        for i = 1:n_sources
            U_y = U(i, rng);
            K_y = K(i, rng(end));
            
            % --- CAPEX ---
            % buildCostYearBySource(i,y) = (costZ(i) / p_step(i)) * K_y;
            buildCostYearBySource(i,y) = (costZ(i) / p_step(i)) * K_y;
            
            % --- OPEX & Externalities ---
            if i == 2 % Solar
                opCost = costU(2) * sum(cf(rng) .* K(2, rng).');
                
                
            elseif i == 5 % Battery
                ChB_year = ChB(rng);
                Ubatt_year = U(5, rng);
                opCost = tau_ch * sum(ChB_year) + tau_dis * sum(Ubatt_year);
           
                
            else % Thermal Sources (Nuclear, Gas, Coal)
                opCost = costU(i) * genYear(i,y);
                extCost= c(i) * genYear(i,y) * EmissionsFactor;
            end
            
            opCostYearBySource(i,y)  = opCost;
            extCostYearBySource(i,y) = extCost;
        end
    end
    
    % 6. Recalculate Totals & LCOE
    capexYear         = sum(buildCostYearBySource, 1);
    opexYear          = sum(opCostYearBySource, 1);
    ExternalitiesYear = sum(extCostYearBySource, 1);
    
    totalAnnualCost_actual = opexYear + capexYear + ExternalitiesYear;
    
    lcoeYear_MWh = totalAnnualCost_actual ./ max(1, elecYear);
    lcoeYear_kWh = lcoeYear_MWh / 1000;
    LCOE_AllYears_kWh = (sum(totalAnnualCost_actual) / max(1, sum(elecYear))) / 1000;
    
    % 7. Pack everything back into RES_new
    RES_new.opCostYearBySource     = opCostYearBySource;
    RES_new.extCostYearBySource    = extCostYearBySource;
    RES_new.buildCostYearBySource  = buildCostYearBySource;
    RES_new.ExternalitiesYear      = ExternalitiesYear;
    RES_new.capexYear              = capexYear;
    RES_new.opexYear               = opexYear;
    RES_new.totalAnnualCost_actual = totalAnnualCost_actual;
    RES_new.lcoeYear_kWh               = lcoeYear_kWh;
    RES_new.LCOE_AllYears_NIS_per_kWh  = LCOE_AllYears_kWh;
    RES_new.TotalExternalities_AllYears = sum(ExternalitiesYear);
    RES_new.TotalOPEX_AllYears         = sum(opexYear);
    RES_new.TotalCAPEX_AllYears        = sum(capexYear);
    RES_new.TotalCost_AllYears         = sum(totalAnnualCost_actual);

end

function PLOT_SENSITIVITY_ANALYSIS(solutions, techNames)
% PLOT_SENSITIVITY_ANALYSIS
% Plots a multi-line chart showing how changing the OPEX cost of individual 
% technologies impacts the total system cost.
% Input 'solutions' is a matrix with columns: [Multiplier, SourceID, TotalCost]

    % Get unique multipliers and sources from the matrix
    multipliers = unique(solutions(:, 1));
    sources = unique(solutions(:, 2));
    n_sources = length(sources);

    % Default technology names if not provided
    if nargin < 2 || isempty(techNames)
        techNames = cell(1, max(sources));
        for i = 1:max(sources)
            if i == 1, techNames{i} = 'Nuclear';
            elseif i == 2, techNames{i} = 'Solar';
            elseif i == 3, techNames{i} = 'Gas';
            elseif i == 4, techNames{i} = 'Coal';
            elseif i == 5, techNames{i} = 'Battery';
            else, techNames{i} = sprintf('Tech %d', i);
            end
        end
    end

    % --- Define Colors (Matching previous charts) ---
    baseColors = [
        0.25 0.35 0.65; % 1: Blue (Nuclear)
        0.90 0.75 0.20; % 2: Yellow (Solar)
        0.75 0.25 0.25; % 3: Red (Gas)
        0.55 0.40 0.65; % 4: Purple (Coal)
        0.35 0.65 0.40; % 5: Green (Battery)
    ];

    % --- Setup Figure ---
    fig = figure('Color','w','Position',[200 150 900 600], 'Name', 'Sensitivity Analysis');
    ax = axes(fig);
    hold(ax, 'on'); box(ax, 'on'); grid(ax, 'on');

    % --- Plot a line for each technology ---
    for i = 1:n_sources
        s = sources(i);
        
        % Filter data for the current source
        idx = solutions(:, 2) == s;
        data_s = solutions(idx, :);
        
        % Sort by multiplier (just to be safe so the line draws left-to-right)
        [~, sortIdx] = sort(data_s(:, 1));
        data_s = data_s(sortIdx, :);
        
        % Extract X (Multipliers) and Y (Total Cost in Billions)
        X = data_s(:, 1);
        Y = data_s(:, 3) / 1e9; 
        
        % Get color safely
        if s <= size(baseColors, 1)
            c = baseColors(s, :);
        else
            c = rand(1, 3);
        end
        
        % Plot the line with markers
        plot(ax, X, Y, '-o', 'LineWidth', 2.5, 'MarkerSize', 8, ...
             'MarkerFaceColor', 'w', 'MarkerEdgeColor', c, 'Color', c, ...
             'DisplayName', techNames{s});
    end

    % --- Formatting ---
    % Add a vertical dashed line at x=1 (Base Case)
    yl = ylim(ax);
    plot(ax, [1 1], yl, 'k--', 'LineWidth', 1, 'HandleVisibility', 'off'); % HandleVisibility off hides it from legend
    
    xlabel(ax, 'Price Multiplier (relative to base cost)', 'FontWeight', 'bold', 'FontSize', 11);
    ylabel(ax, 'Total System Cost [Billion NIS]', 'FontWeight', 'bold', 'FontSize', 11);
    title(ax, 'Sensitivity Analysis: Impact of Component Cost on Total Budget', 'FontSize', 14);
    
    % Customize X-axis ticks to show exactly the multipliers tested
    xticks(ax, multipliers);
    xticklabels(ax, cellstr(num2str(multipliers, '%.2fx')));
    
    % Legend
    legend(ax, 'Location', 'northwest', 'FontSize', 10);
    
end