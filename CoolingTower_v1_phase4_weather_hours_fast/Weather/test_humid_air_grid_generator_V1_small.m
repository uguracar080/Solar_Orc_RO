% TEST_HUMID_AIR_GRID_GENERATOR_V1_SMALL
% Small humid-air database generation and direct HAPropsSI comparison.

clearvars
clc

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
addpath(scriptDir);

outDir = fullfile(scriptDir,'test_outputs');
if ~exist(outDir,'dir')
    mkdir(outDir);
end

opts = struct();
opts.N_Tdb = 10;
opts.N_Twb = 10;
opts.N_RH = 9;
opts.N_P = 4;
opts.N_Tsat = 24;
opts.outputDir = outDir;
opts.fileSuffix = 'V1_SMALL';
opts.showProgress = false;
opts.generateDbWb = false;

db = humid_air_grid_generator_V1(opts);

localAssertFinite(db.dbrh,'dbrh',0.99);
localAssertFinite(db.sat,'sat',0.99);

P = mean(db.dbrh.P_Pa);
Tdb = mean(db.dbrh.Tdb_C);
RH = mean(db.dbrh.RH);

omega_grid = interpn(db.dbrh.Tdb_C,db.dbrh.RH,db.dbrh.P_Pa, ...
    db.dbrh.omega,Tdb,RH,P,'linear');
h_grid = interpn(db.dbrh.Tdb_C,db.dbrh.RH,db.dbrh.P_Pa, ...
    db.dbrh.h_Jkgda,Tdb,RH,P,'linear');
Twb_grid = interpn(db.dbrh.Tdb_C,db.dbrh.RH,db.dbrh.P_Pa, ...
    db.dbrh.Twb_C,Tdb,RH,P,'linear');

omega_cp = HAPropsSI('W','T',Tdb+273.15,'P',P,'R',RH);
h_cp = HAPropsSI('H','T',Tdb+273.15,'P',P,'R',RH);
Twb_cp = HAPropsSI('Twb','T',Tdb+273.15,'P',P,'R',RH) - 273.15;

fprintf('dbrh midpoint rel err: omega %.3g, h %.3g, Twb abs %.3g C\n', ...
    localRelErr(omega_grid,omega_cp),localRelErr(h_grid,h_cp),abs(Twb_grid-Twb_cp));

Tsat = mean(db.sat.T_C);
h_sat_grid = interpn(db.sat.T_C,db.sat.P_Pa,db.sat.h_sat_Jkgda,Tsat,P,'linear');
omega_sat_grid = interpn(db.sat.T_C,db.sat.P_Pa,db.sat.omega_sat,Tsat,P,'linear');
h_sat_cp = HAPropsSI('H','T',Tsat+273.15,'P',P,'R',1.0);
omega_sat_cp = HAPropsSI('W','T',Tsat+273.15,'P',P,'R',1.0);

fprintf('sat midpoint rel err : omega %.3g, h %.3g\n', ...
    localRelErr(omega_sat_grid,omega_sat_cp),localRelErr(h_sat_grid,h_sat_cp));

fprintf('\nSmall humid-air generator test finished successfully.\n');

function localAssertFinite(st,labelText,minRatio)
fields = fieldnames(st);
for i = 1:numel(fields)
    val = st.(fields{i});
    if isnumeric(val) && numel(val) > 1
        ratio = nnz(isfinite(val))/numel(val);
        fprintf('%-6s %-14s finite %.4f\n',labelText,fields{i},ratio);
        assert(ratio >= minRatio, ...
            'Finite ratio too low for %s.%s: %.4f',labelText,fields{i},ratio);
    end
end
end

function err = localRelErr(a,b)
err = abs(a-b)/max(abs(b),eps);
end
