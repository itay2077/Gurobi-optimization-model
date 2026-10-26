function P = machine_paths()
% MACHINE_PATHS  Paths that differ between computers. The only place to edit them.
%   P.runsRoot    folder that holds OPT_ONE_SENS\ (run outputs and the registry)
%   P.xlsFile     model input workbook
%   P.gurobiPath  Gurobi MATLAB interface
% Check the computer name with: getenv('COMPUTERNAME')
    switch upper(getenv('COMPUTERNAME'))
        case 'RAZIEL-LAB'                                   % lab computer
            P.runsRoot   = 'D:\optimization_runs';
            P.xlsFile    = 'D:\optimization_model\ROTH 1 Model - Itay.xlsx';
            P.gurobiPath = 'D:\gurobi1303\win64\matlab';    % check the Gurobi folder on the lab PC
        otherwise                                           % personal computer
            P.runsRoot   = 'C:\Users\nhmu1\OneDrive\Desktop\עבודה עוזר מחקר\MODEL optimization-Itay';
            P.xlsFile    = [P.runsRoot '\ROTH 1 Model - Itay.xlsx'];
            P.gurobiPath = 'C:\gurobi1302\win64\matlab';
    end
end
