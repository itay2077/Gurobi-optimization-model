function S = find_scenarios(varargin)
% FIND_SCENARIOS  Scenarios of the run registry that match the given attributes.
%
%   S = find_scenarios('Objective','emissions', 'Nuclear',false, 'Beta',0.3, 'Area',850, 'Budget',420)
%
%   Name-value options (all optional):
%     'Version'   version number (default: the highest version with an index)
%     'Run'       run number(s)
%     'Objective' 'emissions' | 'cost'
%     'Nuclear'   true | false
%     'Ramp'      'sched7' | 'const4' | 'sched9' | ...
%     'Beta'      value(s) of beta
%     'Budget'    NIS, or 10^9 NIS if < 1e6 (420 = 420e9)
%     'Area'      land cap(s) [km2]
%     'Status'    default "OPTIMAL"; "" = all statuses
%     'Root'      registry root (default registry_root())
%
%   S is a table with the index columns (ScenarioID, Run, Beta, Budget, Area,
%   Status, Cost_bn, Emissions_Mt, RE2050, ...) plus FullPath and ResultsFile.

    p = inputParser;
    addParameter(p, 'Version',   []);
    addParameter(p, 'Run',       []);
    addParameter(p, 'Objective', "");
    addParameter(p, 'Nuclear',   []);
    addParameter(p, 'Ramp',      "");
    addParameter(p, 'Beta',      []);
    addParameter(p, 'Budget',    []);
    addParameter(p, 'Area',      []);
    addParameter(p, 'Status',    "OPTIMAL");
    addParameter(p, 'RETarget',    []);
    addParameter(p, 'Root',      registry_root());
    parse(p, varargin{:});
    o = p.Results;

    [Scen, vdir, V] = local_index(o.Root, o.Version);
    m = true(height(Scen), 1);
    if ~isempty(o.RETarget) && ismember('RETarget2050', Scen.Properties.VariableNames)
        m = m & ismembertol(Scen.RETarget2050, o.RETarget, 1e-9, 'DataScale', 1);
    end
    if ~isempty(o.Run),                     m = m & ismember(Scen.Run, o.Run); end
    if strlength(string(o.Objective)) > 0,  m = m & strcmpi(Scen.Objective, string(o.Objective)); end
    if ~isempty(o.Nuclear),                 m = m & (Scen.Nuclear == double(o.Nuclear)); end
    if strlength(string(o.Ramp)) > 0,       m = m & strcmpi(Scen.Ramp, string(o.Ramp)); end
    if ~isempty(o.Beta),                    m = m & ismembertol(Scen.Beta, o.Beta, 1e-9, 'DataScale', 1); end
    if ~isempty(o.Budget)
        b = o.Budget(:)';  b(b < 1e6) = b(b < 1e6) * 1e9;
        m = m & ismembertol(Scen.Budget, b, 1e6, 'DataScale', 1);
    end
    if ~isempty(o.Area),                    m = m & ismember(Scen.Area, o.Area); end
    if strlength(string(o.Status)) > 0,     m = m & (Scen.Status == string(o.Status)); end

    S = Scen(m, :);
    if height(S) > 0
        S.FullPath    = fullfile(string(vdir), S.RelPath);
        S.ResultsFile = fullfile(S.FullPath, "results_heavy.mat");
    end
    fprintf('find_scenarios: V%d, %d scenarios match.\n', V, height(S));
end

function [Scen, vdir, V] = local_index(root, V)
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
    L = load(f, 'Scen');  Scen = L.Scen;
end
