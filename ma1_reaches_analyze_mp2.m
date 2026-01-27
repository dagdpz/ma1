function details = ma1_reaches_analyze_mp(input_path, animal_name, session_date)
% ma1_reaches_analyze_mp - Modernized daily analysis with silent CLI and Excel export.
%
% Requirements implemented:
% - No output in Command Window (no fprintf/warning output).
% - Prompt user at end of experiment:
%     "Enter the number of blocks (runs) before injection and after injection:"
% - Analyze run-by-run (block-by-block).
% - Export one Excel file with 4 sheets:
%     Sheet 1: Calculated parameters before injection
%     Sheet 2: Analysis plots before injection
%     Sheet 3: Calculated parameters after injection
%     Sheet 4: Analysis plots after injection
% - Include all runs recorded on same experimental day (all *.mat in same folder).
%
% Usage:
%   details = ma1_reaches_analyze_mp('/path/to/one_run.mat', 'Fen');
%   details = ma1_reaches_analyze_mp('/path/to/day_folder', 'Fen', datetime(2025,11,18));

    % Keep MATLAB quiet
    prevWarn = warning('query', 'all');
    warning('off', 'all');
    c = onCleanup(@() warning(prevWarn));

    if nargin < 1 || isempty(input_path)
        error('Input path is required (file or folder).');
    end
    if nargin < 2 || isempty(animal_name)
        animal_name = infer_animal_name(input_path);
    end
    if nargin < 3 || isempty(session_date)
        session_date = datetime('today');
    end

    % Collect all run files for the day
    run_files = list_day_runs(input_path);
    if isempty(run_files)
        error('No .mat files found for the day.');
    end

    % Prompt at end of experiment for blocks before/after injection
    [n_before, n_after] = prompt_blocks_before_after();
    if n_before + n_after > numel(run_files)
        error('Not enough runs found: requested %d (before+after), found %d.', n_before+n_after, numel(run_files));
    end

    before_files = run_files(1:n_before);
    after_files  = run_files((n_before+1):(n_before+n_after));

    % Analyze each run and build parameter tables
    before_tbl = analyze_runs_to_table(before_files, 'Before');
    after_tbl  = analyze_runs_to_table(after_files,  'After');

    % Create plots (same style as older MATLAB plots) and save as PNGs
    out_dir = ensure_output_dir(animal_name);
    date_str = datestr(session_date, 'yyyy-mm-dd');
    excel_filename = sprintf('%s_%s.xlsx', animal_name, date_str);
    excel_fullpath = fullfile(out_dir, excel_filename);

    [before_plot_paths, before_plot_table] = make_plots_for_condition(before_tbl, out_dir, sprintf('%s_%s_before', animal_name, date_str));
    [after_plot_paths,  after_plot_table]  = make_plots_for_condition(after_tbl,  out_dir, sprintf('%s_%s_after',  animal_name, date_str));

    % Export to Excel
    write_tables_and_plots_to_excel(excel_fullpath, before_tbl, before_plot_table, after_tbl, after_plot_table);

    % Return details struct (no printing)
    details = struct();
    details.animal_name = animal_name;
    details.session_date = session_date;
    details.run_files = run_files;
    details.n_before = n_before;
    details.n_after = n_after;
    details.excel_fullpath = excel_fullpath;
    details.before_plot_files = before_plot_paths;
    details.after_plot_files = after_plot_paths;
    details.before_table = before_tbl;
    details.after_table = after_tbl;

function position = get_target_pos(trial)
    % Target position based on x_hnd at state=5
    position = NaN;
    
    if isfield(trial, 'x_hnd') && isfield(trial, 'state') && ...
       ~isempty(trial.x_hnd) && ~isempty(trial.state)
        
        state5_indices = find(trial.state == 5);
        if ~isempty(state5_indices)
            last_state5_idx = state5_indices(end);
            if last_state5_idx <= length(trial.x_hnd)
                final_x_value = trial.x_hnd(last_state5_idx);
                if final_x_value < 0
                    position = 1; % Left side
                elseif final_x_value > 0
                    position = 2; % Right side
                end
            end
        end
    end

function x_position = get_target_x_position(trial)
    % the actual x position value at state=5
    x_position = NaN;
    
    if isfield(trial, 'x_hnd') && isfield(trial, 'state') && ...
       ~isempty(trial.x_hnd) && ~isempty(trial.state)
        
        state5_indices = find(trial.state == 5);
        if ~isempty(state5_indices)
            last_state5_idx = state5_indices(end);
            if last_state5_idx <= length(trial.x_hnd)
                x_position = trial.x_hnd(last_state5_idx);
            end
        end
    end

% =========================
% Modernized helpers
% =========================

function animal_name = infer_animal_name(input_path)
    if isfolder(input_path)
        [~, animal_name] = fileparts(input_path);
        return;
    end
    [parent_path, ~, ~] = fileparts(input_path);
    [~, animal_name] = fileparts(parent_path);

function run_files = list_day_runs(input_path)
    if isfolder(input_path)
        day_dir = input_path;
    else
        day_dir = fileparts(input_path);
    end
    d = dir(fullfile(day_dir, '*.mat'));
    if isempty(d)
        run_files = {};
        return;
    end
    % Sort by name (typical *_01, *_02, ...). If you need by date, change here.
    [~, idx] = sort({d.name});
    d = d(idx);
    run_files = fullfile({d.folder}, {d.name});

function [n_before, n_after] = prompt_blocks_before_after()
    prompt = "Enter the number of blocks (runs) before injection and after injection:";
    while true
        s = strtrim(input(prompt + newline, 's'));
        nums = sscanf(s, '%d %d');
        if numel(nums) == 2 && all(nums >= 0)
            n_before = nums(1);
            n_after = nums(2);
            return;
        end
    end

function out_dir = ensure_output_dir(animal_name)
    base_excel_dir = '/Users/maria/Documents/exel';
    out_dir = fullfile(base_excel_dir, animal_name);
    if ~exist(out_dir, 'dir')
        mkdir(out_dir);
    end

function tbl = analyze_runs_to_table(run_files, condition_label)
    n = numel(run_files);
    rows = cell(n, 1);
    for k = 1:n
        rows{k} = analyze_single_run(run_files{k}, k, condition_label);
    end
    tbl = vertcat(rows{:});

function run_tbl = analyze_single_run(filepath, run_index, condition_label)
    data = load(filepath);
    if ~isfield(data, 'trial')
        error('File does not contain variable "trial": %s', filepath);
    end
    trials = data.trial;

    % Basic counts
    all_trials = length(trials);
    successful_trials = sum([trials.success] == 1);
    failed_trials = sum([trials.success] == 0);
    initiated_trials = successful_trials + failed_trials;

    % Reach hand counts (all trials) - robust to non-scalar reach_hand
    left_hand_all = 0;
    right_hand_all = 0;
    for ii = 1:length(trials)
        rh = get_scalar_num_field(trials(ii), 'reach_hand');
        if rh == 1
            left_hand_all = left_hand_all + 1;
        elseif rh == 2
            right_hand_all = right_hand_all + 1;
        end
    end

    % Compute target side (only success, consistent with old logic)
    left_targets_all = 0;
    right_targets_all = 0;

    instructed_LL = 0; instructed_LR = 0; instructed_RL = 0; instructed_RR = 0;
    free_LL = 0; free_LR = 0; free_RL = 0; free_RR = 0;

    % Delay period outcomes (if available)
    delay_success_count = 0;
    delay_fail_count = 0;
    delay_total_known = 0;

    % Aborted trials (if available)
    aborted_trials_count = 0;
    abort_reason_labels = {};
    abort_reason_counts = [];

    % Reach-hand analysis by task type
    free_left_total = 0; free_left_success = 0;
    free_right_total = 0; free_right_success = 0;
    instructed_left_total = 0; instructed_left_success = 0;
    instructed_right_total = 0; instructed_right_success = 0;

    for i = 1:length(trials)
        trial = trials(i);

        target_position = get_target_pos(trial); % 1 left, 2 right

        if isfield(trial, 'reach_hand') && isfield(trial, 'choice')
            if trial.choice == 1 % FREE
                if trial.reach_hand == 1
                    free_left_total = free_left_total + 1;
                    if trial.success
                        free_left_success = free_left_success + 1;
                    end
                elseif trial.reach_hand == 2
                    free_right_total = free_right_total + 1;
                    if trial.success
                        free_right_success = free_right_success + 1;
                    end
                end
            else % INSTRUCTED
                if trial.reach_hand == 1
                    instructed_left_total = instructed_left_total + 1;
                    if trial.success
                        instructed_left_success = instructed_left_success + 1;
                    end
                elseif trial.reach_hand == 2
                    instructed_right_total = instructed_right_total + 1;
                    if trial.success
                        instructed_right_success = instructed_right_success + 1;
                    end
                end
            end
        end

        if ~trial.success
            continue;
        end

        if ~isnan(target_position)
            if target_position == 1
                left_targets_all = left_targets_all + 1;
            elseif target_position == 2
                right_targets_all = right_targets_all + 1;
            end
        end

        if ~isfield(trial, 'reach_hand') || ~isfield(trial, 'choice') || isnan(target_position)
            continue;
        end

        if trial.choice == 0 % INSTRUCTED
            if trial.reach_hand == 1 && target_position == 1
                instructed_LL = instructed_LL + 1;
            elseif trial.reach_hand == 1 && target_position == 2
                instructed_LR = instructed_LR + 1;
            elseif trial.reach_hand == 2 && target_position == 1
                instructed_RL = instructed_RL + 1;
            elseif trial.reach_hand == 2 && target_position == 2
                instructed_RR = instructed_RR + 1;
            end
        else % FREE
            if trial.reach_hand == 1 && target_position == 1
                free_LL = free_LL + 1;
            elseif trial.reach_hand == 1 && target_position == 2
                free_LR = free_LR + 1;
            elseif trial.reach_hand == 2 && target_position == 1
                free_RL = free_RL + 1;
            elseif trial.reach_hand == 2 && target_position == 2
                free_RR = free_RR + 1;
            end
        end

        % Delay outcome
        d_outcome = get_delay_outcome(trial); % 1 success, 0 fail, NaN unknown
        if ~isnan(d_outcome)
            delay_total_known = delay_total_known + 1;
            if d_outcome == 1
                delay_success_count = delay_success_count + 1;
            elseif d_outcome == 0
                delay_fail_count = delay_fail_count + 1;
            end
        end

        % Aborted trial flag + reason
        if get_aborted_flag(trial) == 1
            aborted_trials_count = aborted_trials_count + 1;
            reason = get_abort_reason(trial);
            if ~isempty(reason)
                % accumulate counts by reason label
                idx = find(strcmp(abort_reason_labels, reason), 1);
                if isempty(idx)
                    abort_reason_labels{end+1} = reason; %#ok<AGROW>
                    abort_reason_counts(end+1) = 1; %#ok<AGROW>
                else
                    abort_reason_counts(idx) = abort_reason_counts(idx) + 1;
                end
            end
        end
    end

    % Success percentages
    if all_trials > 0
        pct_initiated_all = initiated_trials / all_trials * 100;
        pct_success_all = successful_trials / all_trials * 100;
    else
        pct_initiated_all = NaN;
        pct_success_all = NaN;
    end
    if initiated_trials > 0
        pct_success_initiated = successful_trials / initiated_trials * 100;
    else
        pct_success_initiated = NaN;
    end

    % Reach-hand success rates
    free_left_sr = safe_pct(free_left_success, free_left_total);
    free_right_sr = safe_pct(free_right_success, free_right_total);
    instructed_left_sr = safe_pct(instructed_left_success, instructed_left_total);
    instructed_right_sr = safe_pct(instructed_right_success, instructed_right_total);

    % Build compact string summary of abort reasons: "reason1:n1; reason2:n2"
    abort_reason_summary = "";
    for i = 1:numel(abort_reason_labels)
        if i > 1
            abort_reason_summary = abort_reason_summary + "; ";
        end
        abort_reason_summary = abort_reason_summary + sprintf('%s:%d', abort_reason_labels{i}, abort_reason_counts(i));
    end
    abort_reason_summary = string(abort_reason_summary);

    run_tbl = table( ...
        string(condition_label), run_index, string(filepath), all_trials, initiated_trials, successful_trials, failed_trials, ...
        pct_initiated_all, pct_success_all, pct_success_initiated, ...
        left_hand_all, right_hand_all, left_targets_all, right_targets_all, ...
        instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
        free_LL, free_LR, free_RL, free_RR, ...
        free_left_total, free_left_success, free_left_sr, ...
        free_right_total, free_right_success, free_right_sr, ...
        instructed_left_total, instructed_left_success, instructed_left_sr, ...
        instructed_right_total, instructed_right_success, instructed_right_sr, ...
        delay_total_known, delay_success_count, delay_fail_count, aborted_trials_count, abort_reason_summary, ...
        'VariableNames', { ...
            'Condition','Run','File','AllTrials','InitiatedTrials','SuccessfulTrials','FailedTrials', ...
            'PctInitiatedOfAll','PctSuccessfulOfAll','PctSuccessfulOfInitiated', ...
            'LeftHandAll','RightHandAll','LeftTargets','RightTargets', ...
            'Instr_LL','Instr_LR','Instr_RL','Instr_RR', ...
            'Free_LL','Free_LR','Free_RL','Free_RR', ...
            'FreeLeftTotal','FreeLeftSuccess','FreeLeftSuccessPct', ...
            'FreeRightTotal','FreeRightSuccess','FreeRightSuccessPct', ...
            'InstrLeftTotal','InstrLeftSuccess','InstrLeftSuccessPct', ...
            'InstrRightTotal','InstrRightSuccess','InstrRightSuccessPct', ...
            'DelayTotalKnown','DelaySuccess','DelayFail','AbortedTrials','AbortedReasons' ...
        });

function pct = safe_pct(x, n)
    if n > 0
        pct = x / n * 100;
    else
        pct = NaN;
    end

function v = get_scalar_num_field(tr, fieldname)
    % Returns a scalar numeric value from a field or NaN if missing/invalid.
    v = NaN;
    if ~isfield(tr, fieldname)
        return;
    end
    val = tr.(fieldname);
    if isempty(val) || ~isnumeric(val)
        return;
    end
    v = val(1);

function d = get_delay_outcome(tr)
    % Returns 1 (success), 0 (fail), or NaN (unknown) for delay period outcome.
    % Tries several possible field names/types.
    d = NaN;
    candidate_fields = {'delay_success','delaySuccess','delay_outcome','delayOutcome','delay'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
            if isempty(val)
                continue;
            end
            if islogical(val) || isnumeric(val)
                v = val(1);
                if v == 1
                    d = 1; return;
                elseif v == 0
                    d = 0; return;
                end
            elseif ischar(val) || isstring(val)
                sval = lower(string(val(1)));
                if sval == "success"
                    d = 1; return;
                elseif sval == "fail" || sval == "failure" || sval == "unsuccessful"
                    d = 0; return;
                end
            end
        end
    end

function f = get_aborted_flag(tr)
    % Returns 1 if trial is marked as aborted in any reasonable field, else 0.
    f = 0;
    candidate_fields = {'aborted','abort','isAborted','trial_aborted','is_abort'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
            if isempty(val)
                continue;
            end
            if islogical(val) || isnumeric(val)
                v = val(1);
                if v ~= 0
                    f = 1;
                    return;
                end
            elseif ischar(val) || isstring(val)
                sval = lower(string(val(1)));
                if sval == "aborted" || sval == "abort" || sval == "yes" || sval == "true"
                    f = 1;
                    return;
                end
            end
        end
    end

function reason = get_abort_reason(tr)
    % Returns a short text label describing abort reason, or '' if unknown.
    reason = '';
    candidate_fields = {'abort_reason','abortReason','aborted_reason', ...
                        'error','error_code','errorCode','fail_reason','failReason'};
    for i = 1:numel(candidate_fields)
        fn = candidate_fields{i};
        if isfield(tr, fn)
            val = tr.(fn);
            if isempty(val)
                continue;
            end
            if ischar(val) || isstring(val)
                s = strtrim(string(val(1)));
                if s ~= ""
                    reason = char(s);
                    return;
                end
            elseif isnumeric(val)
                reason = sprintf('%s_%g', fn, val(1));
                return;
            end
        end
    end

function [plot_paths, plot_table] = make_plots_for_condition(tbl, out_dir, base_name)
    % Create the same plots as before, but aggregated across runs:
    % - Combination counts (Free and Instructed)
    % - Ipsi vs Contra
    %
    % Save each figure as PNG (offscreen). Excel sheet will contain hyperlinks.

    % Aggregate across runs
    sum_free_LL = nansum(tbl.Free_LL);
    sum_free_LR = nansum(tbl.Free_LR);
    sum_free_RL = nansum(tbl.Free_RL);
    sum_free_RR = nansum(tbl.Free_RR);
    sum_instr_LL = nansum(tbl.Instr_LL);
    sum_instr_LR = nansum(tbl.Instr_LR);
    sum_instr_RL = nansum(tbl.Instr_RL);
    sum_instr_RR = nansum(tbl.Instr_RR);

    total_success = nansum(tbl.SuccessfulTrials);
    free_success = sum_free_LL + sum_free_LR + sum_free_RL + sum_free_RR;
    instr_success = sum_instr_LL + sum_instr_LR + sum_instr_RL + sum_instr_RR;
    free_pct = safe_pct(free_success, total_success);
    instr_pct = safe_pct(instr_success, total_success);

    plot_paths = {};

    % Figure: combinations (free)
    f1 = figure('Visible','off','Position',[50 50 700 500]);
    create_combination_plot(sum_free_LL, sum_free_LR, sum_free_RL, sum_free_RR, 'Free Choice', free_success, free_pct);
    p1 = fullfile(out_dir, [base_name '_free_combinations.png']);
    exportgraphics(f1, p1, 'Resolution', 200);
    close(f1);
    plot_paths{end+1,1} = p1;

    % Figure: combinations (instructed)
    f2 = figure('Visible','off','Position',[50 50 700 500]);
    create_combination_plot(sum_instr_LL, sum_instr_LR, sum_instr_RL, sum_instr_RR, 'Instructed', instr_success, instr_pct);
    p2 = fullfile(out_dir, [base_name '_instructed_combinations.png']);
    exportgraphics(f2, p2, 'Resolution', 200);
    close(f2);
    plot_paths{end+1,1} = p2;

    % Figure: ipsi vs contra
    f3 = figure('Visible','off','Position',[50 50 700 500]);
    create_ipsi_contra_plot(sum_free_LL, sum_free_LR, sum_free_RL, sum_free_RR, sum_instr_LL, sum_instr_LR, sum_instr_RL, sum_instr_RR);
    p3 = fullfile(out_dir, [base_name '_ipsi_contra.png']);
    exportgraphics(f3, p3, 'Resolution', 200);
    close(f3);
    plot_paths{end+1,1} = p3;

    % Build a small table for the Excel "plots" sheet with hyperlinks.
    link_cells = cell(numel(plot_paths), 2);
    for i = 1:numel(plot_paths)
        [~, nm, ext] = fileparts(plot_paths{i});
        label = [nm ext];
        % Excel hyperlink formula (macOS-friendly): use file:/// URL
        url = ['file:///' strrep(plot_paths{i}, filesep, '/')];
        link_cells{i,1} = label;
        link_cells{i,2} = sprintf('=HYPERLINK("%s","Open")', url);
    end
    plot_table = cell2table(link_cells, 'VariableNames', {'PlotFile','Link'});

function write_tables_and_plots_to_excel(excel_path, before_tbl, before_plots_tbl, after_tbl, after_plots_tbl)
    % Overwrite existing file
    if exist(excel_path, 'file')
        delete(excel_path);
    end

    % Excel sheet name limit is 31 characters -> keep names short & stable
    writetable(before_tbl, excel_path, 'Sheet', 'Before_Params');
    writetable(before_plots_tbl, excel_path, 'Sheet', 'Before_Plots');
    writetable(after_tbl,  excel_path, 'Sheet', 'After_Params');
    writetable(after_plots_tbl,  excel_path, 'Sheet', 'After_Plots');

function create_all_plots(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR, ...
                         free_success_count, free_percentage, instructed_success_count, instructed_percentage, ...
                         total_success_count, filepath)
    
    fig = figure('Position', [50, 50, 1400, 1000], 'Name', 'Comprehensive Analysis Results');
    
    subplot(2, 2, 1);
    create_combination_plot(free_LL, free_LR, free_RL, free_RR, 'Free Choice', free_success_count, free_percentage);
    
    subplot(2, 2, 2);
    create_combination_plot(instructed_LL, instructed_LR, instructed_RL, instructed_RR, 'Instructed', instructed_success_count, instructed_percentage);
    
    subplot(2, 2, 3);
    create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR);
    
    [~, name, ext] = fileparts(filepath);
    sgtitle(sprintf('Comprehensive Analysis - %s%s', name, ext), 'FontSize', 16, 'FontWeight', 'bold');

function create_combination_plot(LL, LR, RL, RR, task_name, success_count, percentage)
    data = [LL, LR, RL, RR];
    colors = [0.2, 0.6, 0.8; 0.4, 0.8, 1.0; 0.4, 1.0, 0.8; 0.2, 0.8, 0.6];
    labels = {'L-H/L-T', 'L-H/R-T', 'R-H/L-T', 'R-H/R-T'};
    
    if sum(data) > 0
        bar_handle = bar(data, 'FaceColor', 'flat');
        bar_handle.CData = colors;
        set(gca, 'XTickLabel', labels, 'FontWeight', 'bold');
        ylabel('Number of trials', 'FontWeight', 'bold');
        
        title(sprintf('%s\n%d trials (%.1f%%)', task_name, success_count, percentage), ...
              'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        
        total = sum(data);
        for i = 1:4
            if data(i) > 0
                percent_val = (data(i) / total) * 100;
                text(i, data(i), sprintf('%d\n(%.1f%%)', data(i), percent_val), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontWeight', 'bold', 'FontSize', 10);
            end
        end
    else
        text(0.5, 0.5, 'No data available', ...
             'HorizontalAlignment', 'center', 'VerticalAlignment', 'middle', ...
             'FontSize', 12, 'FontWeight', 'bold');
    end

function create_ipsi_contra_plot(free_LL, free_LR, free_RL, free_RR, instructed_LL, instructed_LR, instructed_RL, instructed_RR)
    free_ipsi = free_LL + free_RR;
    free_contra = free_LR + free_RL;
    instructed_ipsi = instructed_LL + instructed_RR;
    instructed_contra = instructed_LR + instructed_RL;
    
    data = [free_ipsi, free_contra; instructed_ipsi, instructed_contra];
    labels = {'Free Choice', 'Instructed'};
    type_labels = {'Ipsilateral', 'Contralateral'};
    
    colors = [1.0, 1.0, 0; 0.8, 0.4, 0.4];
    
    bar_handle = bar(data, 'grouped');
    
    for i = 1:length(bar_handle)
        bar_handle(i).FaceColor = colors(i,:);
    end
    
    set(gca, 'XTickLabel', labels, 'FontWeight', 'bold');
    ylabel('Number of trials', 'FontWeight', 'bold');
    title('Ipsilateral vs Contralateral Choices', 'FontSize', 12, 'FontWeight', 'bold');
    legend(type_labels, 'Location', 'northeast');
    grid on;
    
    for i = 1:2
        total = sum(data(i,:));
        for j = 1:2
            if data(i,j) > 0
                percent_val = (data(i,j) / total) * 100;
                text(i + (j-1.5)*0.2, data(i,j), sprintf('%d\n(%.1f%%)', data(i,j), percent_val), ...
                     'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                     'FontWeight', 'bold', 'FontSize', 9);
            end
        end
    end