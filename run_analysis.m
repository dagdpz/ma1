% Script to run ma1_reaches_analyze_mp2 analysis
% This script runs the analysis for the example session

addpath('C:\Users\MPuchik\Documents\GitHub\ma1');

% Set parameters
input_path = 'C:\Users\MPuchik\Dropbox\DAG\Maria\20260116';
animal_name = 'Fen';
session_date = datetime(2026,1,16);

% Note: The function will prompt for number of blocks before/after injection
% For this example, let's assume 1 before and 2 after (you can modify as needed)
fprintf('Running analysis for session: %s\n', input_path);
fprintf('Animal: %s\n', animal_name);
fprintf('Date: %s\n', datestr(session_date));
fprintf('\n');
fprintf('The function will prompt you to enter:\n');
fprintf('  "Enter the number of blocks (runs) before injection and after injection:"\n');
fprintf('  Example: "1 2" (for 1 before, 2 after)\n');
fprintf('\n');

% Run the analysis
try
    details = ma1_reaches_analyze_mp(input_path, animal_name, session_date);
    
    fprintf('\n=== ANALYSIS COMPLETED SUCCESSFULLY ===\n');
    fprintf('Excel file saved to: %s\n', details.excel_fullpath);
    fprintf('Before trials table: %d rows\n', height(details.before_trials_table));
    fprintf('After trials table: %d rows\n', height(details.after_trials_table));
    
    % Display sample of trial data
    if height(details.before_trials_table) > 0
        fprintf('\nSample Before trials (first 5 rows):\n');
        disp(details.before_trials_table(1:min(5, height(details.before_trials_table)), :));
    end
    
    if height(details.after_trials_table) > 0
        fprintf('\nSample After trials (first 5 rows):\n');
        disp(details.after_trials_table(1:min(5, height(details.after_trials_table)), :));
    end
    
catch ME
    fprintf('Error occurred: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (line %d)\n', ME.stack(i).file, ME.stack(i).line);
    end
    rethrow(ME);
end
