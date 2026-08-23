function FigureResults = generate_all_figures_v1(Results,figuresRoot)
%GENERATE_ALL_FIGURES_V1 Generate and save all standard V1 result figures.

if nargin < 2 || isempty(figuresRoot)
    if isfield(Results,'cfg') && isfield(Results.cfg,'outputs') && ...
            isfield(Results.cfg.outputs,'figures_root')
        figuresRoot = Results.cfg.outputs.figures_root;
    elseif isfield(Results,'cfg') && isfield(Results.cfg,'project_root')
        figuresRoot = fullfile(Results.cfg.project_root,'Results');
    else
        figuresRoot = fullfile(pwd,'Results');
    end
end

if ~isfolder(figuresRoot)
    mkdir(figuresRoot);
end

generatedRoot = fullfile(figuresRoot,'generated_figures');
if ~isfolder(generatedRoot)
    mkdir(generatedRoot);
end

tag = char(datetime('now','Format','yyyyMMdd_HHmmss'));
outDir = fullfile(generatedRoot,['figures_' tag]);
mkdir(outDir);

Hourly = Results.Hourly;
Summary = Results.Summary;
cfg = Results.cfg;

files = strings(0,1);
files(end+1,1) = fig_power_balance_v1(Hourly,Summary,cfg,outDir);
files(end+1,1) = fig_solar_evaporator_v1(Hourly,Summary,cfg,outDir);
files(end+1,1) = fig_water_balance_v1(Hourly,Summary,cfg,outDir);
files(end+1,1) = fig_temperatures_v1(Hourly,Summary,cfg,outDir);
files(end+1,1) = fig_status_counts_v1(Hourly,Summary,cfg,outDir);

FigureResults = struct();
FigureResults.output_dir = outDir;
FigureResults.files = files;
end
