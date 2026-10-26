function [K, scenRoot, run] = find_run_kpi(varargin)
% FIND_RUN_KPI  KPI table of ONE registered run, found by its attributes.
% Drop-in replacement for local_loadKPI in the plotting codes:
%
%   [K, scenRoot] = find_run_kpi('Objective','emissions', 'Nuclear',false, ...
%                                'Ramp','sched7', 'BetaSweep',false);
%
%   Name-value options (all optional):
%     'Version', 'Run', 'Objective', 'Nuclear', 'Ramp', 'BetaSweep',
%     'Name' (part of the run name), 'OnlyOptimal' (default true), 'Root'
%     'Prompt'    text shown in the selection window (what this run is for)
%     'AlwaysAsk' true = show the selection window even if only one run matches
%
%   K        KPI table of the run (OPTIMAL rows only by default) + column ScenarioID
%   scenRoot <run folder>\scenarios  (char), as returned by local_loadKPI
%   run      the run's row of the index (RunID, Name, Description, ...)
%   If more than one run matches, a window lists them and you choose one.
%   If no run matches, all registered runs are listed and an error is raised.

    p = inputParser;
    addParameter(p, 'Version',     []);
    addParameter(p, 'Run',         []);
    addParameter(p, 'Objective',   "");
    addParameter(p, 'Nuclear',     []);
    addParameter(p, 'Ramp',        "");
    addParameter(p, 'BetaSweep',   []);
    addParameter(p, 'Name',        "");
    addParameter(p, 'OnlyOptimal', true);
    addParameter(p, 'RETarget',    []);
    addParameter(p, 'Root',        registry_root());
    addParameter(p, 'Prompt',      "");
    addParameter(p, 'AlwaysAsk',   false);
    parse(p, varargin{:});
    o = p.Results;

    [Runs, vdir, V] = local_runs(o.Root, o.Version);
    m = true(height(Runs), 1);
    if ~isempty(o.RETarget) && ismember('RETarget2050', Runs.Properties.VariableNames)
        m = m & ismembertol(Runs.RETarget2050, o.RETarget, 1e-9, 'DataScale', 1);
    end
    if ~isempty(o.Run),                    m = m & ismember(Runs.Run, o.Run); end
    if strlength(string(o.Objective)) > 0, m = m & strcmpi(Runs.Objective, string(o.Objective)); end
    if ~isempty(o.Nuclear),                m = m & (Runs.Nuclear == double(o.Nuclear)); end
    if strlength(string(o.Ramp)) > 0,      m = m & strcmpi(Runs.Ramp, string(o.Ramp)); end
    if ~isempty(o.BetaSweep),              m = m & (Runs.BetaSweep == double(o.BetaSweep)); end
    if strlength(string(o.Name)) > 0,      m = m & contains(Runs.Name, string(o.Name), 'IgnoreCase', true); end

    cols = {'RunID', 'Name', 'Objective', 'Nuclear', 'Ramp', 'BetaSweep', 'N_scenarios', 'N_optimal', 'Description'};
    if ~any(m)
        fprintf('\nRuns registered in V%d:\n', V);  disp(Runs(:, cols));
        error('find_run_kpi: no run matches the query.');
    elseif sum(m) > 1 || o.AlwaysAsk
        idx = find(m);
        labels = compose("%s   %s   (%d/%d OPTIMAL)   %s", Runs.RunID(idx), Runs.Name(idx), ...
            Runs.N_optimal(idx), Runs.N_scenarios(idx), Runs.Description(idx));
        prm = {sprintf('%d runs match in V%d. Select one:', numel(idx), V)};
        if strlength(string(o.Prompt)) > 0, prm = [{char(o.Prompt)}, prm]; end
        [sel, ok] = listdlg('ListString', cellstr(labels), 'SelectionMode', 'single', ...
            'PromptString', prm, 'Name', 'find_run_kpi', 'ListSize', [900 200]);
        if ~ok, error('find_run_kpi: no run selected.'); end
        m = false(size(m));  m(idx(sel)) = true;
    end
    run  = Runs(m, :);
    rdir = fullfile(vdir, char(run.RunFolder));

    fm = fullfile(rdir, 'tables', 'KPI_summary.mat');
    fc = fullfile(rdir, 'tables', 'KPI_summary.csv');
    if isfile(fm)
        L = load(fm, 'KPI');  K = L.KPI;
    elseif isfile(fc)
        K = readtable(fc);
    else
        error('No KPI_summary in %s', fullfile(rdir, 'tables'));
    end
    K.Scenario = string(K.Scenario);
    if o.OnlyOptimal
        K = K(string(K.ResultStatus) == "OPTIMAL", :);
    end
    sid = nan(height(K), 1);
    for k = 1:height(K)
        tok = regexp(char(K.Scenario(k)), '(?:^|_)S(\d+)_', 'tokens', 'once');
        if ~isempty(tok), sid(k) = str2double(tok{1}); end
    end
    n = height(K);
    K.ScenarioID = compose("V%d-R%02d-S%03d", repmat(V, n, 1), repmat(run.Run, n, 1), sid);

    scenRoot = fullfile(rdir, 'scenarios');
    fprintf('find_run_kpi: %s  %s  (%d scenarios)\n', run.RunID, run.Name, height(K));
end

function [Runs, vdir, V] = local_runs(root, V)
    if isempty(V)
        d = dir(fullfile(root, 'V*'));  V = 0;
        for k = 1:numel(d)
            tok = regexp(d(k).name, '^V(\d+)$', 'tokens', 'once');
            if d(k).isdir && ~isempty(tok) && isfile(fullfile(root, d(k).name, [d(k).name '_index.mat']))
                V = max(V, str2double(tok{1}));
            end
        end
        if V == 0, error('No version index found under %s.', root); end
    end
    vdir = fullfile(root, sprintf('V%d', V));
    f = fullfile(vdir, sprintf('V%d_index.mat', V));
    if ~isfile(f), error('No index for V%d. Run registry(''rebuild'', %d).', V, V); end
    L = load(f, 'Runs');  Runs = L.Runs;
end
