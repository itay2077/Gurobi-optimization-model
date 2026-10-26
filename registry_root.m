function root = registry_root()
% REGISTRY_ROOT  Root folder of the run registry (contains V1, V2, ...).
% Same folder as fullfile(runsRoot, 'OPT_ONE_SENS') in OPT_ONE_SENS; paths are set in machine_paths.m
    P = machine_paths();
    root = fullfile(P.runsRoot, 'OPT_ONE_SENS');
end
