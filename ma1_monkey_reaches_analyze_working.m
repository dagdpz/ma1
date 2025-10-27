function [left_reaches, right_reaches, details] = ma1_monkey_reaches_analyze_working(filepath)
% Reaches hand analysis 
    
    fprintf('=== REACHES HAND ANALYSIS ===\n');
    
    % LOAD DATA
    data = load(filepath);
    trials = data.trial;
    
    % Initialization of counters
    counters = struct();
    counters.total = length(trials);
    counters.hand = 0;
    counters.eye = 0;
    counters.both = 0;
    counters.success = 0;
    counters.hand_success = 0;
    counters.left = 0;
    counters.right = 0;
    counters.choice = 0;
    counters.instructed = 0;
    
    % Analysis by effector type
    effectors = [trials.effector];
    counters.hand = sum(effectors == 1);
    counters.eye = sum(effectors == 0);
    counters.both = sum(effectors == 2);
    
    % Analysis by success
    successes = [trials.success];
    counters.success = sum(successes);
    
    % Detailed analysis of each trial
    for i = 1:length(trials)
        trial = trials(i);
        
        if trial.effector == 1 && trial.success % hand trials
            counters.hand_success = counters.hand_success + 1;
            
            % Determining the direction
            if isfield(trial, 'target_selected') && length(trial.target_selected) >= 2
                hand_target = trial.target_selected(2);
                
                if hand_target == 1
                    counters.left = counters.left + 1;
                elseif hand_target == 2
                    counters.right = counters.right + 1;
                end
            end
            
            % Choice vs Instructed
            if trial.choice
                counters.choice = counters.choice + 1;
            else
                counters.instructed = counters.instructed + 1;
            end
        end
    end
    
    % Display detailed statistics
    fprintf('\n=== STATISTICS ===\n');
    fprintf('Total trials: %d\n', counters.total);
    fprintf('Effector - Hand: %d, Eyes: %d, Both: %d\n', ...
        counters.hand, counters.eye, counters.both);
    fprintf('Successful trials: %d (%.1f%%)\n', ...
        counters.success, (counters.success/counters.total)*100);
    fprintf('Successful hand trials: %d\n', counters.hand_success);
    
    fprintf('\n=== HAND MOVEMENTS ===\n');
    fprintf('Left (L): %d\n', counters.left);
    fprintf('Right (R): %d\n', counters.right);
    fprintf('Total: %d\n', counters.left + counters.right);
    
    if (counters.left + counters.right) > 0
        fprintf('Ratio L:R = %.2f:1\n', counters.left/counters.right);
        fprintf('Percentage left: %.1f%%\n', (counters.left/(counters.left+counters.right))*100);
        fprintf('Percentage right: %.1f%%\n', (counters.right/(counters.left+counters.right))*100);
    end
    
    fprintf('\n=== ADDITIONALLY ===\n');
    fprintf('Choice trials: %d\n', counters.choice);
    fprintf('Instructed trials: %d\n', counters.instructed);
    
    % Plotting graphs inside a function
    create_reach_plots(counters.left, counters.right, counters, filepath);
    
    left_reaches = counters.left;
    right_reaches = counters.right;
    details = counters;
    
    % Nested function for graphs
    function create_reach_plots(left, right, details, filepath)
        figure('Position', [100, 100, 1200, 400], 'Name', 'Hand movement analysis');
        
        % Graph 1: Pie Chart
        subplot(1,3,1);
        if left + right > 0
            pie_data = [left, right];
            pie_labels = {sprintf('Left (L)\n%d (%.1f%%)', left, (left/(left+right))*100), ...
                         sprintf('Right (R)\n%d (%.1f%%)', right, (right/(left+right))*100)};
            h_pie = pie(pie_data, pie_labels);
            
            % Coloring the sections
            colors = [0, 0, 1; 0, 1, 0]; % blue и green
            for i = 1:2:length(h_pie)
                h_pie(i).FaceColor = colors((i+1)/2, :);
            end
        else
            text(0.5, 0.5, 'No data', 'HorizontalAlignment', 'center');
        end
        title('Distribution of directions', 'FontSize', 12, 'FontWeight', 'bold');
        
    % Graph 2: Column Chart
        subplot(1,3,2);
        bar_data = [left, right];
        bar_handle = bar(bar_data, 'FaceColor', 'flat');
        bar_handle.CData(1,:) = [0, 0, 1]; % blue for L
        bar_handle.CData(2,:) = [0, 1, 0]; % green для R
        
        set(gca, 'XTickLabel', {'Left', 'Right'});
        ylabel('Number of movements', 'FontWeight', 'bold');
        title('Absolute values', 'FontSize', 12, 'FontWeight', 'bold');
        grid on;
        
       % Add numbers to columns
        for i = 1:length(bar_data)
            text(i, bar_data(i) + max(bar_data)*0.05, num2str(bar_data(i)), ...
                 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
        end
        
       % Graph 3: General Statistics
        subplot(1,3,3);
        axis off;
        
       % Text information
        stats_text = {
            sprintf('GENERAL STATISTICS'),
            sprintf(''),
            sprintf('Total trials: %d', details.total),
            sprintf('Hand trials: %d', details.hand),
            sprintf('Successful: %d (%.1f%%)', details.success, (details.success/details.total)*100),
            sprintf(''),
            sprintf('HAND MOVEMENTS:'),
            sprintf('• Left: %d', left),
            sprintf('• Right: %d', right),
            sprintf('• Total: %d', left + right),
            sprintf(''),
            sprintf('RATIO:'),
            sprintf('L:R = %.2f:1', left/right),
            sprintf(''),
            sprintf('PERCENT:'),
            sprintf('• Left: %.1f%%', (left/(left+right))*100),
            sprintf('• Right: %.1f%%', (right/(left+right))*100)
        };
        
        text(0.1, 0.9, stats_text, 'VerticalAlignment', 'top', ...
             'FontName', 'Courier', 'FontSize', 10, 'FontWeight', 'bold');
        
        % General title
        sgtitle(sprintf('Hand movement analysis - %s', extract_filename(filepath)), ...
                'FontSize', 14, 'FontWeight', 'bold', 'Color', [0.1, 0.1, 0.4]);
        
        % Nested function to extract file name
        function filename = extract_filename(fullpath)
            [~, name, ext] = fileparts(fullpath);
            filename = [name ext];
        end
    end
end
