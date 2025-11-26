function [out] = ma1_analyze_reaches(filepath)
% Analyze reach statistics using vectorized operations (no loops)
% Usage: out = ma1_monkey_analyze_reaches('E:\Dropbox\DAG\Maria\20251007\Fen2025-10-07_01.mat')
% Created by Cursor AI, without loops

if nargin < 1
    [filename, pathname] = uigetfile('*.mat', 'Select data file');
    filepath = [pathname filesep filename];
end
load(filepath);

fprintf('\n=== REACH ANALYSIS (VECTORIZED) ===\n');
fprintf('File: %s\n', filepath);
fprintf('Total trials: %d\n', length(trial));

%% Get indices using vectorized operations
idx_hand        = find([trial.effector] == 1);
idx_success     = find([trial.success] == 1);
idx_fail        = find([trial.success] == 0);
idx_hand_succ   = intersect(idx_hand, idx_success);
idx_hand_fail   = intersect(idx_hand, idx_fail);
idx_choice      = find([trial.choice] == 1);
idx_instructed  = find([trial.choice] == 0);

idx_choice_succ     = intersect(idx_choice, idx_hand_succ);
idx_instructed_succ = intersect(idx_instructed, idx_hand_succ);
idx_choice_fail     = intersect(idx_choice, idx_hand_fail);
idx_instructed_fail = intersect(idx_instructed, idx_hand_fail);

fprintf('\nSuccessful hand reaches: %d\n', length(idx_hand_succ));
fprintf('  Instructed: %d\n', length(idx_instructed_succ));
fprintf('  Choice: %d\n', length(idx_choice_succ));
fprintf('\nUnsuccessful hand reaches: %d\n', length(idx_hand_fail));
fprintf('  Instructed: %d\n', length(idx_instructed_fail));
fprintf('  Choice: %d\n', length(idx_choice_fail));

%% Extract hand used for all successful hand trials
reach_hand_all = [trial(idx_hand_succ).reach_hand]'; % 1=left, 2=right (column vector)

%% Extract target information using vectorized operations
% Get target_selected for successful hand trials (2nd element = hand target)
target_selected_temp = cat(1, trial(idx_hand_succ).target_selected);
target_selected = target_selected_temp(:, 2); % hand target index

% Extract x positions using arrayfun (necessary here due to variable-sized tar arrays)
% Note: arrayfun is internally a loop but more compact than explicit for-loop
target_x = arrayfun(@(i) trial(idx_hand_succ(i)).hnd.tar(target_selected(i)).x, ...
                    1:length(idx_hand_succ))';

target_hemifield = (target_x >= 0) + 1; % 1=left (x<0), 2=right (x>=0)

%% Instructed trials analysis
if ~isempty(idx_instructed_succ)
    % Find indices within the idx_hand_succ array
    [~, loc_instructed] = ismember(idx_instructed_succ, idx_hand_succ);
    
    reach_hand_inst = reach_hand_all(loc_instructed);
    hemifield_inst = target_hemifield(loc_instructed);
    
    % Count combinations using logical indexing
    out.instructed.left_hand_left   = sum((reach_hand_inst == 1) & (hemifield_inst == 1));
    out.instructed.left_hand_right  = sum((reach_hand_inst == 1) & (hemifield_inst == 2));
    out.instructed.right_hand_left  = sum((reach_hand_inst == 2) & (hemifield_inst == 1));
    out.instructed.right_hand_right = sum((reach_hand_inst == 2) & (hemifield_inst == 2));
else
    out.instructed.left_hand_left   = 0;
    out.instructed.left_hand_right  = 0;
    out.instructed.right_hand_left  = 0;
    out.instructed.right_hand_right = 0;
end

%% Choice trials analysis (successful)
if ~isempty(idx_choice_succ)
    [~, loc_choice] = ismember(idx_choice_succ, idx_hand_succ);
    
    reach_hand_choice = reach_hand_all(loc_choice);
    hemifield_choice = target_hemifield(loc_choice);
    
    out.choice.left_hand_left   = sum((reach_hand_choice == 1) & (hemifield_choice == 1));
    out.choice.left_hand_right  = sum((reach_hand_choice == 1) & (hemifield_choice == 2));
    out.choice.right_hand_left  = sum((reach_hand_choice == 2) & (hemifield_choice == 1));
    out.choice.right_hand_right = sum((reach_hand_choice == 2) & (hemifield_choice == 2));
else
    out.choice.left_hand_left   = 0;
    out.choice.left_hand_right  = 0;
    out.choice.right_hand_left  = 0;
    out.choice.right_hand_right = 0;
end

%% FAILED TRIALS ANALYSIS
out.num_early_aborts = 0; % Initialize

if ~isempty(idx_hand_fail)
    % Extract target information for failed trials
    target_selected_temp_fail = cat(1, trial(idx_hand_fail).target_selected);
    target_selected_fail = target_selected_temp_fail(:, 2);
    
    % Only analyze failed trials where target was selected (not early aborts)
    valid_target_mask = ~isnan(target_selected_fail);
    idx_hand_fail_valid = idx_hand_fail(valid_target_mask);
    target_selected_fail_valid = target_selected_fail(valid_target_mask);
    
    out.num_early_aborts = length(idx_hand_fail) - length(idx_hand_fail_valid);
    
    % Get early abort indices
    idx_early_abort = idx_hand_fail(~valid_target_mask);
    
    if ~isempty(idx_hand_fail_valid)
        % Extract hand used for failed trials with valid targets
        reach_hand_all_fail = [trial(idx_hand_fail_valid).reach_hand]';
        
        target_x_fail = arrayfun(@(i) trial(idx_hand_fail_valid(i)).hnd.tar(target_selected_fail_valid(i)).x, ...
                                  1:length(idx_hand_fail_valid))';
        target_hemifield_fail = (target_x_fail >= 0) + 1;
        
        % Instructed failed trials (with valid targets)
        idx_instructed_fail_valid = intersect(idx_instructed_fail, idx_hand_fail_valid);
        if ~isempty(idx_instructed_fail_valid)
            [~, loc_instructed_fail] = ismember(idx_instructed_fail_valid, idx_hand_fail_valid);
            
            reach_hand_inst_fail = reach_hand_all_fail(loc_instructed_fail);
            hemifield_inst_fail = target_hemifield_fail(loc_instructed_fail);
            
            out.failed.instructed.left_hand_left   = sum((reach_hand_inst_fail == 1) & (hemifield_inst_fail == 1));
            out.failed.instructed.left_hand_right  = sum((reach_hand_inst_fail == 1) & (hemifield_inst_fail == 2));
            out.failed.instructed.right_hand_left  = sum((reach_hand_inst_fail == 2) & (hemifield_inst_fail == 1));
            out.failed.instructed.right_hand_right = sum((reach_hand_inst_fail == 2) & (hemifield_inst_fail == 2));
        else
            out.failed.instructed.left_hand_left   = 0;
            out.failed.instructed.left_hand_right  = 0;
            out.failed.instructed.right_hand_left  = 0;
            out.failed.instructed.right_hand_right = 0;
        end
        
        % Choice failed trials (with valid targets)
        idx_choice_fail_valid = intersect(idx_choice_fail, idx_hand_fail_valid);
        if ~isempty(idx_choice_fail_valid)
            [~, loc_choice_fail] = ismember(idx_choice_fail_valid, idx_hand_fail_valid);
            
            reach_hand_choice_fail = reach_hand_all_fail(loc_choice_fail);
            hemifield_choice_fail = target_hemifield_fail(loc_choice_fail);
            
            out.failed.choice.left_hand_left   = sum((reach_hand_choice_fail == 1) & (hemifield_choice_fail == 1));
            out.failed.choice.left_hand_right  = sum((reach_hand_choice_fail == 1) & (hemifield_choice_fail == 2));
            out.failed.choice.right_hand_left  = sum((reach_hand_choice_fail == 2) & (hemifield_choice_fail == 1));
            out.failed.choice.right_hand_right = sum((reach_hand_choice_fail == 2) & (hemifield_choice_fail == 2));
        else
            out.failed.choice.left_hand_left   = 0;
            out.failed.choice.left_hand_right  = 0;
            out.failed.choice.right_hand_left  = 0;
            out.failed.choice.right_hand_right = 0;
        end
    else
        % No valid failed trials (all early aborts)
        out.failed.instructed.left_hand_left   = 0;
        out.failed.instructed.left_hand_right  = 0;
        out.failed.instructed.right_hand_left  = 0;
        out.failed.instructed.right_hand_right = 0;
        out.failed.choice.left_hand_left   = 0;
        out.failed.choice.left_hand_right  = 0;
        out.failed.choice.right_hand_left  = 0;
        out.failed.choice.right_hand_right = 0;
    end
    
    %% EARLY ABORT ANALYSIS
    if ~isempty(idx_early_abort)
        % Filter out early aborts with empty reach_hand (very early aborts)
        has_reach_hand = arrayfun(@(i) ~isempty(trial(idx_early_abort(i)).reach_hand), 1:length(idx_early_abort))';
        idx_early_abort_valid = idx_early_abort(has_reach_hand);
        
        if ~isempty(idx_early_abort_valid)
            % Extract hand for early aborts with valid reach_hand
            reach_hand_abort = [trial(idx_early_abort_valid).reach_hand]';
            
            % Separate instructed vs choice early aborts (only those with valid reach_hand)
            idx_instructed_abort = intersect(idx_instructed, idx_early_abort_valid);
            idx_choice_abort = intersect(idx_choice, idx_early_abort_valid);
        
            % For instructed aborts, check if target was shown
            if ~isempty(idx_instructed_abort)
                [~, loc_inst_abort] = ismember(idx_instructed_abort, idx_early_abort_valid);
                reach_hand_inst_abort = reach_hand_abort(loc_inst_abort);
            
            % Check target presentation and hemifield for instructed aborts
            target_shown_mask = arrayfun(@(i) length(trial(idx_instructed_abort(i)).hnd.tar) >= 1, ...
                                         1:length(idx_instructed_abort))';
            
            % Initialize counters
            out.early_abort.instructed.left_hand_no_target = 0;
            out.early_abort.instructed.left_hand_left_target = 0;
            out.early_abort.instructed.left_hand_right_target = 0;
            out.early_abort.instructed.right_hand_no_target = 0;
            out.early_abort.instructed.right_hand_left_target = 0;
            out.early_abort.instructed.right_hand_right_target = 0;
            
            for i = 1:length(idx_instructed_abort)
                hand = reach_hand_inst_abort(i);
                if target_shown_mask(i)
                    % Target was shown, determine hemifield
                    target_x = trial(idx_instructed_abort(i)).hnd.tar(1).x;
                    target_hemi = (target_x >= 0) + 1; % 1=left, 2=right
                    
                    if hand == 1 && target_hemi == 1
                        out.early_abort.instructed.left_hand_left_target = out.early_abort.instructed.left_hand_left_target + 1;
                    elseif hand == 1 && target_hemi == 2
                        out.early_abort.instructed.left_hand_right_target = out.early_abort.instructed.left_hand_right_target + 1;
                    elseif hand == 2 && target_hemi == 1
                        out.early_abort.instructed.right_hand_left_target = out.early_abort.instructed.right_hand_left_target + 1;
                    elseif hand == 2 && target_hemi == 2
                        out.early_abort.instructed.right_hand_right_target = out.early_abort.instructed.right_hand_right_target + 1;
                    end
                else
                    % No target shown
                    if hand == 1
                        out.early_abort.instructed.left_hand_no_target = out.early_abort.instructed.left_hand_no_target + 1;
                    else
                        out.early_abort.instructed.right_hand_no_target = out.early_abort.instructed.right_hand_no_target + 1;
                    end
                end
            end
        else
            out.early_abort.instructed.left_hand_no_target = 0;
            out.early_abort.instructed.left_hand_left_target = 0;
            out.early_abort.instructed.left_hand_right_target = 0;
            out.early_abort.instructed.right_hand_no_target = 0;
            out.early_abort.instructed.right_hand_left_target = 0;
            out.early_abort.instructed.right_hand_right_target = 0;
            end
            
            % For choice aborts, just count by hand
            if ~isempty(idx_choice_abort)
                [~, loc_choice_abort] = ismember(idx_choice_abort, idx_early_abort_valid);
                reach_hand_choice_abort = reach_hand_abort(loc_choice_abort);
                
                out.early_abort.choice.left_hand = sum(reach_hand_choice_abort == 1);
                out.early_abort.choice.right_hand = sum(reach_hand_choice_abort == 2);
            else
                out.early_abort.choice.left_hand = 0;
                out.early_abort.choice.right_hand = 0;
            end
            
            out.indices.instructed_abort = idx_instructed_abort;
            out.indices.choice_abort = idx_choice_abort;
        else
            % No valid early aborts (all missing reach_hand)
            out.early_abort.instructed.left_hand_no_target = 0;
            out.early_abort.instructed.left_hand_left_target = 0;
            out.early_abort.instructed.left_hand_right_target = 0;
            out.early_abort.instructed.right_hand_no_target = 0;
            out.early_abort.instructed.right_hand_left_target = 0;
            out.early_abort.instructed.right_hand_right_target = 0;
            out.early_abort.choice.left_hand = 0;
            out.early_abort.choice.right_hand = 0;
        end
    else
        % No early aborts
        out.early_abort.instructed.left_hand_no_target = 0;
        out.early_abort.instructed.left_hand_left_target = 0;
        out.early_abort.instructed.left_hand_right_target = 0;
        out.early_abort.instructed.right_hand_no_target = 0;
        out.early_abort.instructed.right_hand_left_target = 0;
        out.early_abort.instructed.right_hand_right_target = 0;
        out.early_abort.choice.left_hand = 0;
        out.early_abort.choice.right_hand = 0;
    end
else
    % No failed trials
    out.failed.instructed.left_hand_left   = 0;
    out.failed.instructed.left_hand_right  = 0;
    out.failed.instructed.right_hand_left  = 0;
    out.failed.instructed.right_hand_right = 0;
    out.failed.choice.left_hand_left   = 0;
    out.failed.choice.left_hand_right  = 0;
    out.failed.choice.right_hand_left  = 0;
    out.failed.choice.right_hand_right = 0;
end

%% Display results
fprintf('\n╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                    INSTRUCTED REACHES                         ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    out.instructed.left_hand_left, out.instructed.left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    out.instructed.right_hand_left, out.instructed.right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    out.instructed.left_hand_left + out.instructed.right_hand_left, ...
    out.instructed.left_hand_right + out.instructed.right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

fprintf('\n╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                       CHOICE REACHES                          ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    out.choice.left_hand_left, out.choice.left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    out.choice.right_hand_left, out.choice.right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    out.choice.left_hand_left + out.choice.right_hand_left, ...
    out.choice.left_hand_right + out.choice.right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

fprintf('\n╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                  FAILED INSTRUCTED REACHES                    ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    out.failed.instructed.left_hand_left, out.failed.instructed.left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    out.failed.instructed.right_hand_left, out.failed.instructed.right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    out.failed.instructed.left_hand_left + out.failed.instructed.right_hand_left, ...
    out.failed.instructed.left_hand_right + out.failed.instructed.right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

fprintf('\n╔═══════════════════════════════════════════════════════════════╗\n');
fprintf('║                    FAILED CHOICE REACHES                      ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════╣\n');
fprintf('║                 │   Left Hemifield  │  Right Hemifield        ║\n');
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Left Hand     │       %3d         │       %3d               ║\n', ...
    out.failed.choice.left_hand_left, out.failed.choice.left_hand_right);
fprintf('║   Right Hand    │       %3d         │       %3d               ║\n', ...
    out.failed.choice.right_hand_left, out.failed.choice.right_hand_right);
fprintf('╠═════════════════╪═══════════════════╪═════════════════════════╣\n');
fprintf('║   Total         │       %3d         │       %3d               ║\n', ...
    out.failed.choice.left_hand_left + out.failed.choice.right_hand_left, ...
    out.failed.choice.left_hand_right + out.failed.choice.right_hand_right);
fprintf('╚═══════════════════════════════════════════════════════════════╝\n');

fprintf('\n╔═══════════════════════════════════════════════════════════════════════════════╗\n');
fprintf('║                     EARLY ABORT INSTRUCTED TRIALS                             ║\n');
fprintf('╠═══════════════════════════════════════════════════════════════════════════════╣\n');
fprintf('║           │ No Target │ Left Target │ Right Target │ Total                   ║\n');
fprintf('╠═══════════╪═══════════╪═════════════╪══════════════╪═════════════════════════╣\n');
fprintf('║ Left Hand │    %3d    │     %3d     │     %3d      │  %3d                    ║\n', ...
    out.early_abort.instructed.left_hand_no_target, ...
    out.early_abort.instructed.left_hand_left_target, ...
    out.early_abort.instructed.left_hand_right_target, ...
    out.early_abort.instructed.left_hand_no_target + out.early_abort.instructed.left_hand_left_target + out.early_abort.instructed.left_hand_right_target);
fprintf('║ Right Hand│    %3d    │     %3d     │     %3d      │  %3d                    ║\n', ...
    out.early_abort.instructed.right_hand_no_target, ...
    out.early_abort.instructed.right_hand_left_target, ...
    out.early_abort.instructed.right_hand_right_target, ...
    out.early_abort.instructed.right_hand_no_target + out.early_abort.instructed.right_hand_left_target + out.early_abort.instructed.right_hand_right_target);
fprintf('╠═══════════╪═══════════╪═════════════╪══════════════╪═════════════════════════╣\n');
fprintf('║ Total     │    %3d    │     %3d     │     %3d      │  %3d                    ║\n', ...
    out.early_abort.instructed.left_hand_no_target + out.early_abort.instructed.right_hand_no_target, ...
    out.early_abort.instructed.left_hand_left_target + out.early_abort.instructed.right_hand_left_target, ...
    out.early_abort.instructed.left_hand_right_target + out.early_abort.instructed.right_hand_right_target, ...
    out.early_abort.instructed.left_hand_no_target + out.early_abort.instructed.left_hand_left_target + out.early_abort.instructed.left_hand_right_target + ...
    out.early_abort.instructed.right_hand_no_target + out.early_abort.instructed.right_hand_left_target + out.early_abort.instructed.right_hand_right_target);
fprintf('╚═══════════════════════════════════════════════════════════════════════════════╝\n');

fprintf('\n╔═════════════════════════════════════════════╗\n');
fprintf('║     EARLY ABORT CHOICE TRIALS               ║\n');
fprintf('╠═════════════════════════════════════════════╣\n');
fprintf('║  Left Hand:  %3d                            ║\n', out.early_abort.choice.left_hand);
fprintf('║  Right Hand: %3d                            ║\n', out.early_abort.choice.right_hand);
fprintf('║  Total:      %3d                            ║\n', out.early_abort.choice.left_hand + out.early_abort.choice.right_hand);
fprintf('╚═════════════════════════════════════════════╝\n');

%% Summary statistics
out.total_instructed = out.instructed.left_hand_left + out.instructed.left_hand_right + ...
                       out.instructed.right_hand_left + out.instructed.right_hand_right;
out.total_choice = out.choice.left_hand_left + out.choice.left_hand_right + ...
                   out.choice.right_hand_left + out.choice.right_hand_right;
out.total_failed_instructed = out.failed.instructed.left_hand_left + out.failed.instructed.left_hand_right + ...
                              out.failed.instructed.right_hand_left + out.failed.instructed.right_hand_right;
out.total_failed_choice = out.failed.choice.left_hand_left + out.failed.choice.left_hand_right + ...
                          out.failed.choice.right_hand_left + out.failed.choice.right_hand_right;
out.total_early_abort_instructed = out.early_abort.instructed.left_hand_no_target + ...
                                   out.early_abort.instructed.left_hand_left_target + ...
                                   out.early_abort.instructed.left_hand_right_target + ...
                                   out.early_abort.instructed.right_hand_no_target + ...
                                   out.early_abort.instructed.right_hand_left_target + ...
                                   out.early_abort.instructed.right_hand_right_target;
out.total_early_abort_choice = out.early_abort.choice.left_hand + out.early_abort.choice.right_hand;

fprintf('\n=== SUMMARY ===\n');
fprintf('Successful Trials:\n');
fprintf('  Instructed: %d\n', out.total_instructed);
fprintf('  Choice: %d\n', out.total_choice);
fprintf('  Total: %d\n', out.total_instructed + out.total_choice);
fprintf('\nFailed Trials (with target selection):\n');
fprintf('  Instructed: %d\n', out.total_failed_instructed);
fprintf('  Choice: %d\n', out.total_failed_choice);
fprintf('  Total: %d\n', out.total_failed_instructed + out.total_failed_choice);
fprintf('\nEarly Aborts:\n');
fprintf('  Instructed: %d\n', out.total_early_abort_instructed);
fprintf('  Choice: %d\n', out.total_early_abort_choice);
fprintf('  Total: %d\n', out.num_early_aborts);
fprintf('\nGrand Total: %d hand reach trials\n', out.total_instructed + out.total_choice + out.total_failed_instructed + out.total_failed_choice + out.num_early_aborts);

%% Calculate choice bias (ipsilateral preference)
if out.total_choice > 0
    ipsi_choice = out.choice.left_hand_left + out.choice.right_hand_right;
    contra_choice = out.choice.left_hand_right + out.choice.right_hand_left;
    
    fprintf('\n=== CHOICE BIAS ===\n');
    fprintf('Ipsilateral choices: %d (%.1f%%)\n', ipsi_choice, 100*ipsi_choice/out.total_choice);
    fprintf('Contralateral choices: %d (%.1f%%)\n', contra_choice, 100*contra_choice/out.total_choice);
    
    out.ipsilateral_pct = 100 * ipsi_choice / out.total_choice;
end

%% Store additional data
out.filepath = filepath;
out.indices.instructed_succ = idx_instructed_succ;
out.indices.choice_succ = idx_choice_succ;
out.indices.hand_succ = idx_hand_succ;
out.indices.instructed_fail = idx_instructed_fail;
out.indices.choice_fail = idx_choice_fail;
out.indices.hand_fail = idx_hand_fail;
out.reach_hand_all = reach_hand_all;
out.target_hemifield_all = target_hemifield;
out.target_x_all = target_x;
if exist('idx_hand_fail_valid', 'var') && ~isempty(idx_hand_fail_valid)
    out.indices.hand_fail_valid = idx_hand_fail_valid;
    out.reach_hand_all_fail = reach_hand_all_fail;
    out.target_hemifield_all_fail = target_hemifield_fail;
    out.target_x_all_fail = target_x_fail;
end

fprintf('\n');

end
