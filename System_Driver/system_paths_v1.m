function Paths = system_paths_v1(ProjectRoot)
%SYSTEM_PATHS_V1 Add V1 system folders and component folders to MATLAB path.

if nargin < 1 || isempty(ProjectRoot)
    thisDir = fileparts(mfilename('fullpath'));
    ProjectRoot = fileparts(thisDir);
end

Paths = struct();
Paths.ProjectRoot = ProjectRoot;
Paths.SystemDriver = fullfile(ProjectRoot,'System_Driver');
Paths.SolarField = fullfile(ProjectRoot,'Solar_Field');
Paths.HeatExchangers = fullfile(ProjectRoot,'Heat_Exchangers');
Paths.ThermalStorage = fullfile(ProjectRoot,'Thermal_Storage');
Paths.ORC = fullfile(ProjectRoot,'ORC_v23');
Paths.CoolingTowerRoot = fullfile(ProjectRoot,'CoolingTower_v1_phase4_weather_hours_fast');
Paths.CoolingTower = fullfile(Paths.CoolingTowerRoot,'CoolingTower');
Paths.Weather = fullfile(ProjectRoot,'Weather');
Paths.Seawater = fullfile(ProjectRoot,'Hourly_profiles_seawater');
Paths.RO = fullfile(ProjectRoot,'RO_MATLAB_Model_v1_8_0_FINAL_DATASET');
Paths.Results = fullfile(ProjectRoot,'Results');
Paths.Figures = fullfile(Paths.SystemDriver,'Figures');

addpath(Paths.SystemDriver,'-begin');
addpath(Paths.SolarField,'-begin');
addpath(Paths.HeatExchangers,'-begin');
addpath(Paths.ThermalStorage,'-begin');
addpath(Paths.ORC,'-begin');
addpath(Paths.CoolingTower,'-begin');
addpath(Paths.Weather,'-begin');
addpath(Paths.Seawater,'-begin');
addpath(Paths.RO,'-begin');
addpath(Paths.Figures,'-begin');

if ~isfolder(Paths.Results)
    mkdir(Paths.Results);
end
end
