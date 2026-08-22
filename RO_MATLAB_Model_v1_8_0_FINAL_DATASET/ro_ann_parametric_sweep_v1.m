%% RO_ANN_PARAMETRIC_SWEEP_V1
% Standalone parametric sweep for the frozen RO ANN surrogate.
%
% This script does not retrain the ANN and does not edit any RO model file.
% It only calls ro_predict_ann_surrogate_v1_9_1.m over a user-editable
% operating grid, then writes time-stamped tables, figures, and a MAT file.

clear all
clc

%% Paths
script_dir = fileparts(mfilename('fullpath'));
addpath(script_dir);

model_file = fullfile(script_dir,'RO_ANN_models_v1_9_1.mat');
results_root = fullfile(script_dir,'parametric_results');

if ~isfile(model_file)
    error('roAnnSweep:ModelFileMissing', ...
        'ANN model file was not found: %s',model_file);
end

if ~exist(results_root,'dir')
    mkdir(results_root);
end

timestamp = datestr(now,'yyyymmdd_HHMMSS');
out_dir = fullfile(results_root,['ro_ann_parametric_sweep_' timestamp]);
mkdir(out_dir);

%% Sweep definition
% Final deployment domain enforced by ro_predict_ann_surrogate_v1_9_1:
%   Qf_train_m3h : 47.5 to 63.0
%   T_RO_in_C    : 20.0 to 45.0
%   Cf_kg_m3     : 38.5 to 41.5
%   R_target     : 0.399 to 0.571
%
% Main purpose for the integrated system discussion:
% quantify whether extra feed preheating keeps improving the RO block, or
% whether the gain becomes small at warm summer inlet temperatures.
%
% User inputs below use this convention:
%   min value
%   max value
%   number of intervals between min and max
%
% Example: min=20, max=45, n_intervals=50 gives 51 grid points because
% both endpoints are included.
Qf_train_m3h_min = 47.5;
Qf_train_m3h_max = 63.0;
Qf_train_m3h_n_intervals = 10;

T_RO_in_C_min = 20.0;
T_RO_in_C_max = 45.0;
T_RO_in_C_n_intervals = 50;

Cf_kg_m3_min = 38.5;
Cf_kg_m3_max = 41.5;
Cf_kg_m3_n_intervals = 10;

R_target_min = 0.400;
R_target_max = 0.570;
R_target_n_intervals = 34;

sweep = struct();
sweep.Qf_train_m3h = localSweepVector( ...
    Qf_train_m3h_min,Qf_train_m3h_max,Qf_train_m3h_n_intervals, ...
    'Qf_train_m3h');
sweep.T_RO_in_C = localSweepVector( ...
    T_RO_in_C_min,T_RO_in_C_max,T_RO_in_C_n_intervals, ...
    'T_RO_in_C');
sweep.Cf_kg_m3 = localSweepVector( ...
    Cf_kg_m3_min,Cf_kg_m3_max,Cf_kg_m3_n_intervals, ...
    'Cf_kg_m3');
sweep.R_target = localSweepVector( ...
    R_target_min,R_target_max,R_target_n_intervals, ...
    'R_target');

% Profile slices used for compact interpretation plots.
profile = struct();
profile.Qf_sweep_index = 2;
profile.Cf_sweep_index = 2;
profile.Qf_train_m3h = sweep.Qf_train_m3h( ...
    min(profile.Qf_sweep_index,numel(sweep.Qf_train_m3h)));
profile.Cf_kg_m3 = sweep.Cf_kg_m3( ...
    min(profile.Cf_sweep_index,numel(sweep.Cf_kg_m3)));

profile.R_target_min = 0.420;
profile.R_target_max = 0.570;
profile.R_target_n_intervals = 3;
profile.R_target_values = localSweepVector( ...
    profile.R_target_min,profile.R_target_max,profile.R_target_n_intervals, ...
    'profile.R_target_values');

%% Compute options
% execution_mode:
%   'auto'       : vectorized for small sweeps, parfor chunking for large sweeps
%   'vectorized' : one direct ANN call for all cases
%   'parfor'     : chunked ANN calls with parfor when Parallel Toolbox exists
compute = struct();
compute.execution_mode = 'auto';
compute.parallel_min_cases = 100000;
compute.parfor_chunk_size = 10000;
compute.max_workers = [];

plot_figures = true;

%% Build cases and call ANN surrogate
fprintf('\nRO ANN parametric sweep\n');
fprintf('Model file : %s\n',model_file);
fprintf('Output dir : %s\n',out_dir);

[QfGrid,TGrid,CfGrid,RGrid] = ndgrid( ...
    sweep.Qf_train_m3h, ...
    sweep.T_RO_in_C, ...
    sweep.Cf_kg_m3, ...
    sweep.R_target);

Inputs = table( ...
    QfGrid(:),TGrid(:),CfGrid(:),RGrid(:), ...
    'VariableNames',{'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target'});

timer_sweep = tic;
Results = localRunAnnSweep(model_file,Inputs,compute);
elapsed_s = toc(timer_sweep);

Results.case_id = (1:height(Results)).';
Results = movevars(Results,'case_id','Before',1);

Timing = struct();
Timing.total_s = elapsed_s;
Timing.n_cases = height(Results);
Timing.seconds_per_case = elapsed_s/max(height(Results),1);
Timing.execution_mode = string(Results.Properties.UserData.execution_mode);
Timing.n_chunks = Results.Properties.UserData.n_chunks;
Timing.parfor_chunk_size = Results.Properties.UserData.parfor_chunk_size;

fprintf('Cases      : %d\n',height(Results));
fprintf('Feasible   : %d / %d\n',nnz(Results.Feasible),height(Results));
fprintf('Execution  : %s',Timing.execution_mode);
if Timing.n_chunks > 1
    fprintf(' (%d chunks)',Timing.n_chunks);
end
fprintf('\n');
fprintf('Elapsed    : %.3f s (%.6f s/case)\n', ...
    Timing.total_s,Timing.seconds_per_case);

%% Reduced result views
BestByState = localBestRecoveryByState(Results);
TemperatureProfileBest = localSelectBestProfile( ...
    BestByState,profile.Qf_train_m3h,profile.Cf_kg_m3);
TemperatureProfilesFixedR = localSelectFixedRecoveryProfiles( ...
    Results,profile.Qf_train_m3h,profile.Cf_kg_m3,profile.R_target_values);
TemperatureSummary = localTemperatureSummary(Results);

%% Save outputs
all_cases_csv = fullfile(out_dir,'ro_ann_parametric_all_cases.csv');
feasible_csv = fullfile(out_dir,'ro_ann_parametric_feasible_cases.csv');
best_csv = fullfile(out_dir,'ro_ann_parametric_best_recovery_by_state.csv');
best_profile_csv = fullfile(out_dir,'ro_ann_temperature_profile_best_recovery.csv');
fixed_profile_csv = fullfile(out_dir,'ro_ann_temperature_profiles_fixed_recovery.csv');
temp_summary_csv = fullfile(out_dir,'ro_ann_temperature_summary.csv');
mat_file = fullfile(out_dir,'ro_ann_parametric_sweep_results.mat');
summary_txt = fullfile(out_dir,'ro_ann_parametric_sweep_summary.txt');

writetable(Results,all_cases_csv);
writetable(Results(Results.Feasible,:),feasible_csv);
writetable(BestByState,best_csv);
writetable(TemperatureProfileBest,best_profile_csv);
writetable(TemperatureProfilesFixedR,fixed_profile_csv);
writetable(TemperatureSummary,temp_summary_csv);

save(mat_file, ...
    'sweep','profile','compute','model_file','out_dir','Results','BestByState', ...
    'TemperatureProfileBest','TemperatureProfilesFixedR', ...
    'TemperatureSummary','Timing','-v7.3');

localWriteSummary(summary_txt,model_file,out_dir,sweep,profile,Results, ...
    BestByState,TemperatureProfileBest,TemperatureSummary,Timing,compute);

figure_files = string.empty(0,1);
if plot_figures
    figure_files = localPlotSweepOutputs(out_dir,Results,BestByState, ...
        TemperatureProfileBest,TemperatureProfilesFixedR,TemperatureSummary,profile);
end

fprintf('\nSaved files:\n');
fprintf('  %s\n',all_cases_csv);
fprintf('  %s\n',feasible_csv);
fprintf('  %s\n',best_csv);
fprintf('  %s\n',best_profile_csv);
fprintf('  %s\n',fixed_profile_csv);
fprintf('  %s\n',temp_summary_csv);
fprintf('  %s\n',mat_file);
fprintf('  %s\n',summary_txt);
for i = 1:numel(figure_files)
    fprintf('  %s\n',figure_files(i));
end
fprintf('\nWorkspace outputs: Results, BestByState, TemperatureProfileBest, TemperatureProfilesFixedR, TemperatureSummary, sweep, profile, Timing\n');

%% Local functions
function Results = localRunAnnSweep(model_file,Inputs,compute)
n_cases = height(Inputs);
mode_requested = lower(string(compute.execution_mode));

if mode_requested == "auto"
    if n_cases >= compute.parallel_min_cases
        mode_requested = "parfor";
    else
        mode_requested = "vectorized";
    end
end

if mode_requested == "parfor" && ~localParallelAvailable()
    warning('roAnnSweep:ParallelUnavailable', ...
        'Parallel Computing Toolbox is not available. Falling back to vectorized mode.');
    mode_requested = "vectorized";
end

if mode_requested == "parfor"
    try
        Results = localRunAnnSweepParfor(model_file,Inputs,compute);
    catch ME
        warning('roAnnSweep:ParforFailed', ...
            'parfor sweep failed (%s). Falling back to vectorized mode.',ME.message);
        Results = localRunAnnSweepVectorized(model_file,Inputs);
    end
else
    Results = localRunAnnSweepVectorized(model_file,Inputs);
end
end

function Results = localRunAnnSweepVectorized(model_file,Inputs)
Results = ro_predict_ann_surrogate_v1_9_1( ...
    model_file, ...
    Inputs.Qf_train_m3h, ...
    Inputs.T_RO_in_C, ...
    Inputs.Cf_kg_m3, ...
    Inputs.R_target);

Results.Properties.UserData = struct( ...
    'execution_mode','vectorized', ...
    'n_chunks',1, ...
    'parfor_chunk_size',height(Inputs));
end

function Results = localRunAnnSweepParfor(model_file,Inputs,compute)
n_cases = height(Inputs);
chunk_size = max(1,round(double(compute.parfor_chunk_size)));
n_chunks = ceil(n_cases/chunk_size);

pool = gcp('nocreate');
if isempty(pool)
    if isempty(compute.max_workers)
        parpool('local');
    else
        parpool('local',compute.max_workers);
    end
end

chunks = cell(n_chunks,1);
parfor i_chunk = 1:n_chunks
    first_row = (i_chunk-1)*chunk_size + 1;
    last_row = min(i_chunk*chunk_size,n_cases);
    row_idx = first_row:last_row;

    chunk = ro_predict_ann_surrogate_v1_9_1( ...
        model_file, ...
        Inputs.Qf_train_m3h(row_idx), ...
        Inputs.T_RO_in_C(row_idx), ...
        Inputs.Cf_kg_m3(row_idx), ...
        Inputs.R_target(row_idx));
    chunks{i_chunk} = chunk;
end

Results = vertcat(chunks{:});
Results.Properties.UserData = struct( ...
    'execution_mode','parfor', ...
    'n_chunks',n_chunks, ...
    'parfor_chunk_size',chunk_size);
end

function tf = localParallelAvailable()
tf = false;
try
    tf = license('test','Distrib_Computing_Toolbox') && ...
        exist('parpool','file') == 2 && exist('gcp','file') == 2;
catch
    tf = false;
end
end

function values = localSweepVector(v_min,v_max,n_intervals,var_name)
v_min = double(v_min);
v_max = double(v_max);
n_intervals = double(n_intervals);

if ~isscalar(v_min) || ~isscalar(v_max) || ~isscalar(n_intervals) || ...
        ~isfinite(v_min) || ~isfinite(v_max) || ~isfinite(n_intervals)
    error('roAnnSweep:InvalidSweepInput', ...
        '%s min, max, and n_intervals must be finite scalar values.',var_name);
end

if v_max < v_min
    error('roAnnSweep:InvalidSweepInput', ...
        '%s max value must be greater than or equal to min value.',var_name);
end

if abs(n_intervals-round(n_intervals)) > 1.0e-12 || n_intervals < 0
    error('roAnnSweep:InvalidSweepInput', ...
        '%s n_intervals must be a non-negative integer.',var_name);
end

n_intervals = round(n_intervals);
if n_intervals == 0
    if v_max ~= v_min
        error('roAnnSweep:InvalidSweepInput', ...
            '%s n_intervals can be zero only when min equals max.',var_name);
    end
    values = v_min;
else
    values = linspace(v_min,v_max,n_intervals+1);
end
end

function txt = localVectorDescription(values)
values = double(values(:).');
if isempty(values)
    txt = '[]';
elseif numel(values) == 1
    txt = sprintf('%.6g',values(1));
else
    step = values(2)-values(1);
    is_uniform = all(abs(diff(values)-step) <= max(1.0e-12,1.0e-10*abs(step)));
    if is_uniform
        txt = sprintf('%.6g : %.6g : %.6g  (%d points)', ...
            values(1),step,values(end),numel(values));
    else
        txt = sprintf('%s  (%d points)',mat2str(values,6),numel(values));
    end
end
end

function BestByState = localBestRecoveryByState(Results)
state_matrix = [Results.Qf_train_m3h,Results.T_RO_in_C,Results.Cf_kg_m3];
[states,~,group_id] = unique(state_matrix,'rows','stable');
n_groups = size(states,1);

best_R = NaN(n_groups,1);
best_Qp = NaN(n_groups,1);
best_W = NaN(n_groups,1);
best_SEC = NaN(n_groups,1);
best_Cp = NaN(n_groups,1);
best_P1 = NaN(n_groups,1);
best_P2 = NaN(n_groups,1);
best_Pfeas = NaN(n_groups,1);
feasible_count = zeros(n_groups,1);
candidate_count = zeros(n_groups,1);

for g = 1:n_groups
    idx = group_id == g;
    candidate_count(g) = nnz(idx);
    feasible_idx = idx & Results.Feasible & isfinite(Results.SEC_kWh_m3);
    feasible_count(g) = nnz(feasible_idx);

    if feasible_count(g) > 0
        row_numbers = find(feasible_idx);
        [~,local_best] = min(Results.SEC_kWh_m3(feasible_idx));
        row = row_numbers(local_best);

        best_R(g) = Results.R_target(row);
        best_Qp(g) = Results.Qp_train_m3h(row);
        best_W(g) = Results.W_RO_train_kW(row);
        best_SEC(g) = Results.SEC_kWh_m3(row);
        best_Cp(g) = Results.Cp_mg_L(row);
        best_P1(g) = Results.P1_opt_gauge_MPa(row);
        best_P2(g) = Results.P2_opt_gauge_MPa(row);
        best_Pfeas(g) = Results.P_feasible(row);
    end
end

BestByState = table( ...
    states(:,1),states(:,2),states(:,3),candidate_count,feasible_count, ...
    best_R,best_Qp,best_W,best_SEC,best_Cp,best_P1,best_P2,best_Pfeas, ...
    'VariableNames',{'Qf_train_m3h','T_RO_in_C','Cf_kg_m3', ...
    'candidate_count','feasible_count','best_R_target_min_SEC', ...
    'best_Qp_train_m3h','best_W_RO_train_kW','best_SEC_kWh_m3', ...
    'best_Cp_mg_L','best_P1_opt_gauge_MPa','best_P2_opt_gauge_MPa', ...
    'best_P_feasible'});
end

function Profile = localSelectBestProfile(BestByState,Qf_target,Cf_target)
tol = 1.0e-9;
idx = abs(BestByState.Qf_train_m3h-Qf_target) < tol & ...
    abs(BestByState.Cf_kg_m3-Cf_target) < tol;
Profile = sortrows(BestByState(idx,:),'T_RO_in_C');

if height(Profile) > 0
    Profile.dSEC_dT_forward_kWh_m3K = localForwardSlope( ...
        Profile.T_RO_in_C,Profile.best_SEC_kWh_m3);
    Profile.dW_dT_forward_kW_K = localForwardSlope( ...
        Profile.T_RO_in_C,Profile.best_W_RO_train_kW);
    Profile.dQp_dT_forward_m3h_K = localForwardSlope( ...
        Profile.T_RO_in_C,Profile.best_Qp_train_m3h);
end
end

function FixedProfiles = localSelectFixedRecoveryProfiles(Results,Qf_target,Cf_target,R_values)
tol = 1.0e-9;
FixedProfiles = table();
for i = 1:numel(R_values)
    idx = abs(Results.Qf_train_m3h-Qf_target) < tol & ...
        abs(Results.Cf_kg_m3-Cf_target) < tol & ...
        abs(Results.R_target-R_values(i)) < tol;
    slice = sortrows(Results(idx,:),'T_RO_in_C');
    if height(slice) > 0
        slice.dSEC_dT_forward_kWh_m3K = localForwardSlope( ...
            slice.T_RO_in_C,slice.SEC_kWh_m3);
        FixedProfiles = [FixedProfiles; slice]; %#ok<AGROW>
    end
end
end

function TemperatureSummary = localTemperatureSummary(Results)
[T_values,~,group_id] = unique(Results.T_RO_in_C,'stable');
nT = numel(T_values);

n_cases = zeros(nT,1);
n_domain = zeros(nT,1);
n_feasible = zeros(nT,1);
feasible_fraction = NaN(nT,1);
mean_SEC = NaN(nT,1);
min_SEC = NaN(nT,1);
mean_W = NaN(nT,1);
mean_Qp = NaN(nT,1);
mean_P1 = NaN(nT,1);
mean_P2 = NaN(nT,1);
mean_Cp = NaN(nT,1);

for i = 1:nT
    idx = group_id == i;
    ok = idx & Results.Feasible;
    n_cases(i) = nnz(idx);
    n_domain(i) = nnz(idx & Results.InTrainingDomain);
    n_feasible(i) = nnz(ok);
    feasible_fraction(i) = n_feasible(i)/max(n_cases(i),1);

    mean_SEC(i) = mean(Results.SEC_kWh_m3(ok),'omitnan');
    min_SEC(i) = min(Results.SEC_kWh_m3(ok),[],'omitnan');
    mean_W(i) = mean(Results.W_RO_train_kW(ok),'omitnan');
    mean_Qp(i) = mean(Results.Qp_train_m3h(ok),'omitnan');
    mean_P1(i) = mean(Results.P1_opt_gauge_MPa(ok),'omitnan');
    mean_P2(i) = mean(Results.P2_opt_gauge_MPa(ok),'omitnan');
    mean_Cp(i) = mean(Results.Cp_mg_L(ok),'omitnan');
end

TemperatureSummary = table(T_values,n_cases,n_domain,n_feasible, ...
    feasible_fraction,mean_SEC,min_SEC,mean_W,mean_Qp,mean_P1,mean_P2,mean_Cp, ...
    'VariableNames',{'T_RO_in_C','n_cases','n_in_domain','n_feasible', ...
    'feasible_fraction','mean_SEC_kWh_m3','min_SEC_kWh_m3', ...
    'mean_W_RO_train_kW','mean_Qp_train_m3h','mean_P1_opt_gauge_MPa', ...
    'mean_P2_opt_gauge_MPa','mean_Cp_mg_L'});

TemperatureSummary.dMeanSEC_dT_forward_kWh_m3K = localForwardSlope( ...
    TemperatureSummary.T_RO_in_C,TemperatureSummary.mean_SEC_kWh_m3);
TemperatureSummary.dMinSEC_dT_forward_kWh_m3K = localForwardSlope( ...
    TemperatureSummary.T_RO_in_C,TemperatureSummary.min_SEC_kWh_m3);
end

function slope = localForwardSlope(x,y)
slope = NaN(size(y));
for i = 1:(numel(y)-1)
    if isfinite(x(i)) && isfinite(x(i+1)) && ...
            isfinite(y(i)) && isfinite(y(i+1)) && x(i+1) ~= x(i)
        slope(i) = (y(i+1)-y(i))/(x(i+1)-x(i));
    end
end
end

function localWriteSummary(summary_txt,model_file,out_dir,sweep,profile,Results, ...
    BestByState,TemperatureProfileBest,TemperatureSummary,Timing,compute)
fid = fopen(summary_txt,'w');
if fid < 0
    warning('roAnnSweep:SummaryOpenFailed', ...
        'Could not write summary file: %s',summary_txt);
    return
end
cleanupObj = onCleanup(@() fclose(fid));

fprintf(fid,'RO ANN parametric sweep summary\n');
fprintf(fid,'Generated          : %s\n',datestr(now,'yyyy-mm-dd HH:MM:SS'));
fprintf(fid,'Model file         : %s\n',model_file);
fprintf(fid,'Output directory   : %s\n\n',out_dir);

fprintf(fid,'Sweep axes\n');
fprintf(fid,'Qf_train_m3h       : %s\n',localVectorDescription(sweep.Qf_train_m3h));
fprintf(fid,'T_RO_in_C          : %s\n',localVectorDescription(sweep.T_RO_in_C));
fprintf(fid,'Cf_kg_m3           : %s\n',localVectorDescription(sweep.Cf_kg_m3));
fprintf(fid,'R_target           : %s\n\n',localVectorDescription(sweep.R_target));

fprintf(fid,'Case counts\n');
fprintf(fid,'Total cases        : %d\n',height(Results));
fprintf(fid,'In domain          : %d / %d\n',nnz(Results.InTrainingDomain),height(Results));
fprintf(fid,'Feasible           : %d / %d\n',nnz(Results.Feasible),height(Results));
fprintf(fid,'Requested mode     : %s\n',char(string(compute.execution_mode)));
fprintf(fid,'Actual mode        : %s\n',char(Timing.execution_mode));
fprintf(fid,'Chunks             : %d\n',Timing.n_chunks);
fprintf(fid,'Chunk size         : %d\n',Timing.parfor_chunk_size);
fprintf(fid,'Elapsed time       : %.3f s (%.6f s/case)\n\n', ...
    Timing.total_s,Timing.seconds_per_case);

ok = Results.Feasible;
if any(ok)
    [best_SEC,best_row_local] = min(Results.SEC_kWh_m3(ok));
    feasible_rows = find(ok);
    best_row = feasible_rows(best_row_local);

    fprintf(fid,'Global feasible minimum SEC case\n');
    fprintf(fid,'case_id            : %d\n',Results.case_id(best_row));
    fprintf(fid,'Qf_train_m3h       : %.3f\n',Results.Qf_train_m3h(best_row));
    fprintf(fid,'T_RO_in_C          : %.3f\n',Results.T_RO_in_C(best_row));
    fprintf(fid,'Cf_kg_m3           : %.3f\n',Results.Cf_kg_m3(best_row));
    fprintf(fid,'R_target           : %.3f\n',Results.R_target(best_row));
    fprintf(fid,'SEC_kWh_m3         : %.5f\n',best_SEC);
    fprintf(fid,'W_RO_train_kW      : %.3f\n',Results.W_RO_train_kW(best_row));
    fprintf(fid,'Qp_train_m3h       : %.3f\n',Results.Qp_train_m3h(best_row));
    fprintf(fid,'P1/P2 gauge MPa    : %.3f / %.3f\n\n', ...
        Results.P1_opt_gauge_MPa(best_row),Results.P2_opt_gauge_MPa(best_row));
end

fprintf(fid,'Best-recovery temperature profile slice\n');
fprintf(fid,'Qf_train_m3h       : %.3f\n',profile.Qf_train_m3h);
fprintf(fid,'Cf_kg_m3           : %.3f\n',profile.Cf_kg_m3);
if height(TemperatureProfileBest) > 0
    first_ok = find(isfinite(TemperatureProfileBest.best_SEC_kWh_m3),1,'first');
    last_ok = find(isfinite(TemperatureProfileBest.best_SEC_kWh_m3),1,'last');
    if ~isempty(first_ok) && ~isempty(last_ok)
        fprintf(fid,'First valid T/SEC   : %.3f C / %.5f kWh/m3\n', ...
            TemperatureProfileBest.T_RO_in_C(first_ok), ...
            TemperatureProfileBest.best_SEC_kWh_m3(first_ok));
        fprintf(fid,'Last valid T/SEC    : %.3f C / %.5f kWh/m3\n', ...
            TemperatureProfileBest.T_RO_in_C(last_ok), ...
            TemperatureProfileBest.best_SEC_kWh_m3(last_ok));
    end
end

fprintf(fid,'\nTemperature summary uses all Qf, Cf, and R points.\n');
if height(TemperatureSummary) > 0
    [~,idx_best_mean] = min(TemperatureSummary.mean_SEC_kWh_m3);
    fprintf(fid,'Lowest mean SEC T  : %.3f C\n',TemperatureSummary.T_RO_in_C(idx_best_mean));
    marginal_threshold = 0.010;
    marginal_high_temp_floor_C = 35.0;
    idx_small = find(TemperatureSummary.T_RO_in_C >= marginal_high_temp_floor_C & ...
        abs(TemperatureSummary.dMeanSEC_dT_forward_kWh_m3K) <= ...
        marginal_threshold,1,'first');
    if ~isempty(idx_small)
        fprintf(fid,'Small high-T dSEC/dT : |dSEC/dT| <= %.4f first occurs near %.3f C after %.1f C\n', ...
            marginal_threshold,TemperatureSummary.T_RO_in_C(idx_small), ...
            marginal_high_temp_floor_C);
    else
        fprintf(fid,'Small high-T dSEC/dT : |dSEC/dT| <= %.4f was not reached after %.1f C.\n', ...
            marginal_threshold,marginal_high_temp_floor_C);
    end
end

fprintf(fid,'\nInterpretation note\n');
fprintf(fid,['Use dSEC_dT columns to decide whether one more degree of ' ...
    'feed heating still has meaningful RO value. Small absolute dSEC_dT ' ...
    'at high T means forcing condenser pressure upward for preheating is ' ...
    'likely not worthwhile unless another system-level constraint needs it.\n']);

clear cleanupObj
end

function figure_files = localPlotSweepOutputs(out_dir,Results,BestByState, ...
    BestProfile,FixedProfiles,TemperatureSummary,profile)
figure_files = string.empty(0,1);

figure_files = [figure_files; localPlotFullSweepMaps(out_dir,Results,BestByState)];

if height(BestProfile) > 0
    fig = figure('Name','RO ANN best recovery temperature profile', ...
        'Color','w','Visible','off');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(BestProfile.T_RO_in_C,BestProfile.best_SEC_kWh_m3,'LineWidth',1.5);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Best SEC [kWh/m3]');
    title('Minimum SEC across recovery');

    nexttile;
    plot(BestProfile.T_RO_in_C,BestProfile.best_R_target_min_SEC,'LineWidth',1.5);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Best recovery [-]');
    title('Recovery selected by min SEC');

    nexttile;
    plot(BestProfile.T_RO_in_C,BestProfile.best_W_RO_train_kW,'LineWidth',1.5);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('RO power [kW]');
    title('Power at selected recovery');

    nexttile;
    plot(BestProfile.T_RO_in_C,BestProfile.dSEC_dT_forward_kWh_m3K,'LineWidth',1.5);
    yline(0,'k:','HandleVisibility','off');
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Forward dSEC/dT [kWh/m3-K]');
    title('Marginal SEC change');

    sgtitle(sprintf('Qf = %.1f m3/h, Cf = %.1f kg/m3', ...
        profile.Qf_train_m3h,profile.Cf_kg_m3));
    file = fullfile(out_dir,'fig_temperature_profile_best_recovery.png');
    exportgraphics(fig,file,'Resolution',180);
    close(fig);
    figure_files(end+1,1) = string(file);
end

if height(FixedProfiles) > 0
    fig = figure('Name','RO ANN fixed recovery temperature profiles', ...
        'Color','w','Visible','off');
    tiledlayout(1,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    hold on;
    r_values = unique(FixedProfiles.R_target,'stable');
    for i = 1:numel(r_values)
        idx = abs(FixedProfiles.R_target-r_values(i)) < 1.0e-9;
        plot(FixedProfiles.T_RO_in_C(idx),FixedProfiles.SEC_kWh_m3(idx), ...
            'LineWidth',1.5,'DisplayName',sprintf('R = %.3f',r_values(i)));
    end
    hold off;
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('SEC [kWh/m3]');
    title('SEC at fixed recovery');
    legend('Location','best');

    nexttile;
    hold on;
    for i = 1:numel(r_values)
        idx = abs(FixedProfiles.R_target-r_values(i)) < 1.0e-9;
        plot(FixedProfiles.T_RO_in_C(idx),FixedProfiles.W_RO_train_kW(idx), ...
            'LineWidth',1.5,'DisplayName',sprintf('R = %.3f',r_values(i)));
    end
    hold off;
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('RO power [kW]');
    title('Power at fixed recovery');
    legend('Location','best');

    sgtitle(sprintf('Qf = %.1f m3/h, Cf = %.1f kg/m3', ...
        profile.Qf_train_m3h,profile.Cf_kg_m3));
    file = fullfile(out_dir,'fig_temperature_profiles_fixed_recovery.png');
    exportgraphics(fig,file,'Resolution',180);
    close(fig);
    figure_files(end+1,1) = string(file);
end

if height(TemperatureSummary) > 0
    fig = figure('Name','RO ANN full sweep temperature summary', ...
        'Color','w','Visible','off');
    tiledlayout(2,2,'TileSpacing','compact','Padding','compact');

    nexttile;
    plot(TemperatureSummary.T_RO_in_C,TemperatureSummary.feasible_fraction, ...
        'LineWidth',1.5);
    grid on;
    box on;
    ylim([0 1]);
    xlabel('RO inlet temperature [degC]');
    ylabel('Feasible fraction [-]');
    title('ANN feasible fraction');

    nexttile;
    plot(TemperatureSummary.T_RO_in_C,TemperatureSummary.mean_SEC_kWh_m3, ...
        'LineWidth',1.5);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Mean SEC [kWh/m3]');
    title('Mean feasible SEC');

    nexttile;
    plot(TemperatureSummary.T_RO_in_C,TemperatureSummary.mean_W_RO_train_kW, ...
        'LineWidth',1.5);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Mean RO power [kW]');
    title('Mean feasible power');

    nexttile;
    plot(TemperatureSummary.T_RO_in_C,TemperatureSummary.dMeanSEC_dT_forward_kWh_m3K, ...
        'LineWidth',1.5);
    yline(0,'k:','HandleVisibility','off');
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Forward dSEC/dT [kWh/m3-K]');
    title('Marginal mean SEC change');

    file = fullfile(out_dir,'fig_temperature_summary_all_cases.png');
    exportgraphics(fig,file,'Resolution',180);
    close(fig);
    figure_files(end+1,1) = string(file);
end
end

function figure_files = localPlotFullSweepMaps(out_dir,Results,BestByState)
figure_files = string.empty(0,1);

if height(BestByState) == 0 || height(Results) == 0
    return
end

T_values = unique(BestByState.T_RO_in_C,'stable');
Qf_values = unique(BestByState.Qf_train_m3h,'stable');
Cf_values = unique(BestByState.Cf_kg_m3,'stable');
[n_rows,n_cols] = localTileGrid(numel(Cf_values));

%% Minimum SEC heatmaps over T-Qf, one panel per salinity
fig = figure('Name','RO ANN min SEC map by T, Qf, and Cf', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

for i_cf = 1:numel(Cf_values)
    nexttile;
    Z = localBestStateMatrix(BestByState,T_values,Qf_values,Cf_values(i_cf), ...
        'best_SEC_kWh_m3');
    imagesc(T_values,Qf_values,Z);
    set(gca,'YDir','normal');
    colorbar;
    colormap(gca,parula);
    xlabel('RO inlet temperature [degC]');
    ylabel('Qf [m3/h]');
    title(sprintf('Cf = %.2f kg/m3',Cf_values(i_cf)));
end

sgtitle('Minimum SEC across recovery for every T-Qf-Cf state');
file = fullfile(out_dir,'fig_map_min_SEC_T_Qf_by_Cf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);

%% Recovery selected by the minimum-SEC point
fig = figure('Name','RO ANN best recovery map by T, Qf, and Cf', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

for i_cf = 1:numel(Cf_values)
    nexttile;
    Z = localBestStateMatrix(BestByState,T_values,Qf_values,Cf_values(i_cf), ...
        'best_R_target_min_SEC');
    imagesc(T_values,Qf_values,Z);
    set(gca,'YDir','normal');
    colorbar;
    colormap(gca,parula);
    xlabel('RO inlet temperature [degC]');
    ylabel('Qf [m3/h]');
    title(sprintf('Cf = %.2f kg/m3',Cf_values(i_cf)));
end

sgtitle('Recovery chosen by minimum SEC for every T-Qf-Cf state');
file = fullfile(out_dir,'fig_map_best_R_T_Qf_by_Cf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);

%% Feasible recovery fraction heatmaps
fig = figure('Name','RO ANN feasible fraction map by T, Qf, and Cf', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

for i_cf = 1:numel(Cf_values)
    nexttile;
    Z = localFeasibleFractionMatrix(Results,T_values,Qf_values,Cf_values(i_cf));
    imagesc(T_values,Qf_values,Z);
    set(gca,'YDir','normal');
    caxis([0 1]);
    colorbar;
    colormap(gca,parula);
    xlabel('RO inlet temperature [degC]');
    ylabel('Qf [m3/h]');
    title(sprintf('Cf = %.2f kg/m3',Cf_values(i_cf)));
end

sgtitle('Fraction of feasible recovery targets for every T-Qf-Cf state');
file = fullfile(out_dir,'fig_map_feasible_fraction_T_Qf_by_Cf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);

%% Qf-dependent line plots, one panel per salinity
fig = figure('Name','RO ANN Qf dependent minimum SEC profiles', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

for i_cf = 1:numel(Cf_values)
    nexttile;
    hold on;
    for i_q = 1:numel(Qf_values)
        idx = abs(BestByState.Cf_kg_m3-Cf_values(i_cf)) < 1.0e-9 & ...
            abs(BestByState.Qf_train_m3h-Qf_values(i_q)) < 1.0e-9;
        slice = sortrows(BestByState(idx,:),'T_RO_in_C');
        plot(slice.T_RO_in_C,slice.best_SEC_kWh_m3,'LineWidth',1.4, ...
            'DisplayName',sprintf('Qf %.2f',Qf_values(i_q)));
    end
    hold off;
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Minimum SEC [kWh/m3]');
    title(sprintf('Cf = %.2f kg/m3',Cf_values(i_cf)));
    legend('Location','best');
end

sgtitle('Qf effect on minimum SEC after scanning all recovery targets');
file = fullfile(out_dir,'fig_qf_lines_min_SEC_by_Cf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);

%% Marginal SEC change with temperature for every Qf-Cf state
fig = figure('Name','RO ANN marginal temperature value by Qf and Cf', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

for i_cf = 1:numel(Cf_values)
    nexttile;
    hold on;
    for i_q = 1:numel(Qf_values)
        idx = abs(BestByState.Cf_kg_m3-Cf_values(i_cf)) < 1.0e-9 & ...
            abs(BestByState.Qf_train_m3h-Qf_values(i_q)) < 1.0e-9;
        slice = sortrows(BestByState(idx,:),'T_RO_in_C');
        dsec = localForwardSlope(slice.T_RO_in_C,slice.best_SEC_kWh_m3);
        plot(slice.T_RO_in_C,dsec,'LineWidth',1.4, ...
            'DisplayName',sprintf('Qf %.2f',Qf_values(i_q)));
    end
    hold off;
    yline(0,'k:','HandleVisibility','off');
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('Forward dSEC/dT [kWh/m3-K]');
    title(sprintf('Cf = %.2f kg/m3',Cf_values(i_cf)));
    legend('Location','best');
end

sgtitle('Marginal value of one more degree of RO feed heating');
file = fullfile(out_dir,'fig_qf_lines_marginal_dSEC_by_Cf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);

%% All feasible ANN points as SEC-temperature clouds
fig = figure('Name','RO ANN feasible SEC cloud by salinity', ...
    'Color','w','Visible','off','Position',[100 100 1250 850]);
tiledlayout(n_rows,n_cols,'TileSpacing','compact','Padding','compact');

ok = Results.Feasible & isfinite(Results.SEC_kWh_m3);
for i_cf = 1:numel(Cf_values)
    nexttile;
    idx = ok & abs(Results.Cf_kg_m3-Cf_values(i_cf)) < 1.0e-9;
    scatter(Results.T_RO_in_C(idx),Results.SEC_kWh_m3(idx),18, ...
        Results.Qf_train_m3h(idx),'filled');
    colorbar;
    colormap(gca,parula);
    grid on;
    box on;
    xlabel('RO inlet temperature [degC]');
    ylabel('SEC [kWh/m3]');
    title(sprintf('Cf = %.2f kg/m3, all feasible R',Cf_values(i_cf)));
end

sgtitle('All feasible recovery points; marker color is Qf');
file = fullfile(out_dir,'fig_cloud_all_feasible_SEC_T_colored_by_Qf.png');
exportgraphics(fig,file,'Resolution',180);
close(fig);
figure_files(end+1,1) = string(file);
end

function Z = localBestStateMatrix(BestByState,T_values,Qf_values,Cf_value,var_name)
Z = NaN(numel(Qf_values),numel(T_values));
for i_q = 1:numel(Qf_values)
    for i_t = 1:numel(T_values)
        idx = abs(BestByState.Qf_train_m3h-Qf_values(i_q)) < 1.0e-9 & ...
            abs(BestByState.T_RO_in_C-T_values(i_t)) < 1.0e-9 & ...
            abs(BestByState.Cf_kg_m3-Cf_value) < 1.0e-9;
        if any(idx)
            values = BestByState.(var_name)(idx);
            Z(i_q,i_t) = values(1);
        end
    end
end
end

function Z = localFeasibleFractionMatrix(Results,T_values,Qf_values,Cf_value)
Z = NaN(numel(Qf_values),numel(T_values));
for i_q = 1:numel(Qf_values)
    for i_t = 1:numel(T_values)
        idx = abs(Results.Qf_train_m3h-Qf_values(i_q)) < 1.0e-9 & ...
            abs(Results.T_RO_in_C-T_values(i_t)) < 1.0e-9 & ...
            abs(Results.Cf_kg_m3-Cf_value) < 1.0e-9;
        if any(idx)
            Z(i_q,i_t) = nnz(Results.Feasible(idx))/nnz(idx);
        end
    end
end
end

function [n_rows,n_cols] = localTileGrid(n_tiles)
n_cols = ceil(sqrt(n_tiles));
n_rows = ceil(n_tiles/n_cols);
end
