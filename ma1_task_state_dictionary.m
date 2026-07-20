% ma1_task_state_dictionary.m
% MonkeyPsych state codes and task-type mid-sequences.
%
% SCRIPT (not a function). Run from an analysis entry point so variables
% land in that function's workspace, e.g.:
%   run(fullfile(fileparts(mfilename('fullpath')), 'ma1_task_state_dictionary.m'));
%   % then use STATE.DEL_PER, TASK, STATE_NAME, WIKI_URL
%
% Local functions do NOT see these variables automatically — pass STATE
% (and TASK if needed) as arguments into helpers.
%
% All task types start with INI_TRI and end with ABORT or (SUCCESS + REWARD),
% then ITI. TASK.state_names lists the mid-sequence only (wiki table).
%
% Source: https://github.com/dagdpz/monkeypsych/wiki

WIKI_URL = 'https://github.com/dagdpz/monkeypsych/wiki';

%% State codes
STATE = struct();
STATE.INI_TRI = 1;            % initialize trial
STATE.FIX_ACQ = 2;            % fixation acquisition
STATE.FIX_HOL = 3;            % fixation hold
STATE.TAR_ACQ = 4;            % target acquisition
STATE.TAR_HOL = 5;            % target hold
STATE.CUE_ON = 6;             % cue on
STATE.MEM_PER = 7;            % memory period
STATE.DEL_PER = 8;            % delay period
STATE.TAR_ACQ_INV = 9;        % target acquisition invisible
STATE.TAR_HOL_INV = 10;       % target hold invisible
STATE.MAT_ACQ = 11;           % target acquisition in sample to match
STATE.MAT_HOL = 12;           % target hold in sample to match
STATE.MAT_ACQ_MSK = 13;       % masked sample-to-match acquisition
STATE.MAT_HOL_MSK = 14;       % masked sample-to-match hold
STATE.SEN_RET = 15;           % return to sensors (Poffenberger)
STATE.FIX_PER = 16;           % fixation period (RF cue flashes)
STATE.MSK_HOL = 17;           % mask for delayed M2S
STATE.ABORT = 19;
STATE.SUCCESS = 20;
STATE.REWARD = 21;
STATE.CUE_ON_AUDITIV = 22;    % auditory cue on
STATE.TA2_ACQ = 23;           % second target acquisition (wagering)
STATE.TA2_HOL = 24;           % second target hold
STATE.FI2_ACQ = 25;           % second fixation acquisition
STATE.FI2_HOL = 26;           % second fixation hold
STATE.ITI = 50;
STATE.CLOSE = 99;

%% Reverse lookup: numeric code -> field name
STATE_NAME = containers.Map('KeyType', 'double', 'ValueType', 'char');
stateFields = fieldnames(STATE);
for iField = 1:numel(stateFields)
    STATE_NAME(STATE.(stateFields{iField})) = stateFields{iField};
end

%% Task types (mid-sequence only; type may be non-integer, e.g. 2.5)
% Each entry: .type, .info, .state_names (cellstr), .state_codes (numeric)
taskDefs = { ...
    1,    'fixation', ...
        {'FIX_ACQ', 'FIX_HOL'}; ...
    2,    'direct saccade/reach', ...
        {'FIX_ACQ', 'FIX_HOL', 'TAR_ACQ', 'TAR_HOL'}; ...
    2.5,  'direct saccade/reach with cue distractor', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MEM_PER', 'TAR_ACQ', 'TAR_HOL'}; ...
    3,    'memory', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MEM_PER', 'TAR_ACQ_INV', 'TAR_HOL_INV', 'TAR_ACQ', 'TAR_HOL'}; ...
    4,    'delay', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'DEL_PER', 'TAR_ACQ', 'TAR_HOL'}; ...
    5,    'Search-to-sample', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MEM_PER', 'MAT_ACQ', 'MAT_HOL'}; ...
    6,    'Search-to-sample (masked targets)', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MEM_PER', 'MAT_ACQ_MSK', 'MAT_HOL_MSK'}; ...
    7,    'Poffenberger', ...
        {'FIX_ACQ', 'FIX_HOL', 'TAR_ACQ', 'SEN_RET', 'DEL_PER'}; ...
    8,    'Multiple cue flashes for RF checking', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'FIX_PER'}; ...
    9,    'delayed M2S with backward masking', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MSK_HOL', 'TAR_ACQ', 'TAR_HOL'}; ...
    10,   'delayed M2S with backward masking + Wagering', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'MSK_HOL', 'TAR_ACQ', 'TAR_HOL', ...
         'CUE_ON_AUDITIV', 'FI2_ACQ', 'FI2_HOL', 'TA2_ACQ', 'TA2_HOL'}; ...
    11,   'Fixation with visual cue', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'DEL_PER'}; ...
    12,   'Fixation with auditory cue', ...
        {'FIX_ACQ', 'FIX_HOL', 'CUE_ON', 'CUE_ON_AUDITIV'}; ...
    };

nTask = size(taskDefs, 1);
TASK = struct('type', {}, 'info', {}, 'state_names', {}, 'state_codes', {});
for iTask = 1:nTask
    names = taskDefs{iTask, 3};
    codes = zeros(1, numel(names));
    for iName = 1:numel(names)
        codes(iName) = STATE.(names{iName});
    end
    TASK(iTask).type = taskDefs{iTask, 1};
    TASK(iTask).info = taskDefs{iTask, 2};
    TASK(iTask).state_names = names;
    TASK(iTask).state_codes = codes;
end

clear taskDefs nTask iTask iField iName names codes stateFields;
