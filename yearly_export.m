function T = yearly_export(runDir)
% EXPORT_YEARLY  Collect year-by-year results of every solved scenario in a run
% folder into one CSV file: <runDir>\yearly_summary.csv
%
%   yearly_export                 % opens a folder dialog - pick the run folder
%   yearly_export('D:\...\V4-R03_...')
%
% One row per scenario per year (2023-2050). Scenarios without results_heavy.mat
% (e.g. INFEASIBLE_BUDGET) are skipped automatically.

    if nargin < 1 || isempty(runDir)
        runDir = uigetdir('D:\optimization_runs\OPT_ONE_SENS', 'Choose the run folder');
        if isequal(runDir, 0), disp('Cancelled.'); T = table(); return; end
    end
    d = dir(fullfile(runDir, '**', 'results_heavy.mat'));
    fprintf('Found %d solved scenarios in %s\n', numel(d), runDir);
    if isempty(d), T = table(); return; end

    rows = {};
    for i = 1:numel(d)
        S = load(fullfile(d(i).folder, d(i).name), 'RES');  R = S.RES;
        G = R.genYear;  if size(G,1) ~= 5, G = G.'; end      % sources x years (nuc, PV, gas, coal, storage)
        em = R.emitYear(:).';
        re = 100 * sum(G([1 2 5],:), 1) ./ sum(G, 1);         % nuclear + PV + storage discharge
        [~, sc] = fileparts(d(i).folder);
        for y = 1:size(G,2)
            t = y*8760 - 1;                                   % capacity held during year y
            rows(end+1,:) = {sc, R.meta.maxCost/1e9, R.meta.maxAreaSolar, 2022+y, re(y), em(y)/1e6, ...
                G(2,y)/1e6, G(3,y)/1e6, G(5,y)/1e6, sum(G(:,y))/1e6, ...
                R.K(2,t)/1e3, R.K(3,t)/1e3, R.K(5,t)/1e3}; %#ok<AGROW>
        end
        fprintf('  %2d/%d  %s\n', i, numel(d), sc);
        clear S R
    end
    T = cell2table(rows, 'VariableNames', {'Scenario','Budget_bn','Area_km2','Year','RE_pct','Emis_Mt', ...
        'Solar_TWh','Gas_TWh','Batt_TWh','Total_TWh','K_solar_GW','K_gas_GW','K_batt_GW'});
    outFile = fullfile(runDir, 'yearly_summary.csv');
    writetable(T, outFile);
    fprintf('Done: %d rows written to\n  %s\n', height(T), outFile);
end
