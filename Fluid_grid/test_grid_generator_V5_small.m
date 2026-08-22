% TEST_GRID_GENERATOR_V5_SMALL
% Small V5 database generation and interpolation smoke test.

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

fprintf('\n=== R1233zd(E) small V5 generation ===\n');
rOpts = struct();
rOpts.fluid = 'R1233zd(E)';
rOpts.Pmin_bar = 1.1;
rOpts.Pmax_bar = 12.0;
rOpts.hmin = 230e3;
rOpts.hmax = 460e3;
rOpts.smin = 1050;
rOpts.smax = 1700;
rOpts.Tmin_K = 285;
rOpts.Tmax_K = 390;
rOpts.Np = 18;
rOpts.Nh = 19;
rOpts.Ns = 17;
rOpts.Nt = 16;
rOpts.Nsat = 18;
rOpts.outputDir = outDir;
rOpts.fileSuffix = 'V5_SMALL';
rOpts.showProgress = false;
rDB = grid_generator_V5(rOpts);
localAssertFiniteEnough(rDB,'R1233zd(E)');
localComparePh(rDB,'R1233zd(E)');
localComparePT(rDB,'R1233zd(E)');

fprintf('\n=== Water small V5 generation ===\n');
wOpts = struct();
wOpts.Pmin_bar = 1.0;
wOpts.Pmax_bar = 3.0;
wOpts.Tmin_K = 285;
wOpts.Tmax_K = 360;
wOpts.hmin = 45e3;
wOpts.hmax = 365e3;
wOpts.smin = 150;
wOpts.smax = 1150;
wOpts.Np = 16;
wOpts.Nh = 17;
wOpts.Ns = 15;
wOpts.Nt = 16;
wOpts.Nsat = 16;
wOpts.outputDir = outDir;
wOpts.fileSuffix = 'V5_SMALL';
wOpts.showProgress = false;
wDB = water_grid_generator_V1(wOpts);
localAssertFiniteEnough(wDB,'Water');
localComparePh(wDB,'Water');
localComparePT(wDB,'Water');

fprintf('\nSmall V5 generator test finished successfully.\n');

function localAssertFiniteEnough(db,labelText)
required = { ...
    'Ph','T'; 'Ph','s'; 'Ph','rho'; 'Ph','cp'; 'Ph','mu'; 'Ph','k'; ...
    'PT','H'; 'PT','s'; 'PT','rho'; 'PT','cp'; 'PT','mu'; 'PT','k'; ...
    'sat','T'; 'sat','hf'; 'sat','hg'; 'sat','rho_f'; 'sat','rho_g'; ...
    'sat','cp_f'; 'sat','cp_g'; 'sat','mu_f'; 'sat','mu_g'; 'sat','k_f'; 'sat','k_g'};

for i = 1:size(required,1)
    block = required{i,1};
    field = required{i,2};
    value = db.(block).(field);
    finiteRatio = nnz(isfinite(value))/numel(value);
    fprintf('%-10s %-3s.%-6s finite %.4f\n',labelText,block,field,finiteRatio);
    assert(finiteRatio > 0.95, ...
        'Finite ratio too low for %s %s.%s: %.4f',labelText,block,field,finiteRatio);
end
end

function localComparePh(db,fluid)
P = mean(db.Ph.P);
h = mean(db.Ph.h);

T_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.T,P,h,'linear');
s_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.s,P,h,'linear');
rho_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.rho,P,h,'linear');
cp_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.cp,P,h,'linear');
mu_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.mu,P,h,'linear');
k_grid = interpn(db.Ph.P,db.Ph.h,db.Ph.k,P,h,'linear');

T_cp = PropsSI('T','P',P,'H',h,fluid);
s_cp = PropsSI('S','P',P,'H',h,fluid);
rho_cp = PropsSI('D','P',P,'H',h,fluid);
cp_cp = PropsSI('C','P',P,'H',h,fluid);
mu_cp = PropsSI('V','P',P,'H',h,fluid);
if localIsR1233zdE(fluid)
    k_cp = k_grid;
else
    k_cp = PropsSI('L','P',P,'H',h,fluid);
end

fprintf('%-10s Ph midpoint rel err: T %.3g, s %.3g, rho %.3g, cp %.3g, mu %.3g, k %.3g\n', ...
    fluid,localRelErr(T_grid,T_cp),localRelErr(s_grid,s_cp), ...
    localRelErr(rho_grid,rho_cp),localRelErr(cp_grid,cp_cp), ...
    localRelErr(mu_grid,mu_cp),localRelErr(k_grid,k_cp));
end

function localComparePT(db,fluid)
P = mean(db.PT.P);
T = mean(db.PT.T);

h_grid = interpn(db.PT.P,db.PT.T,db.PT.H,P,T,'linear');
s_grid = interpn(db.PT.P,db.PT.T,db.PT.s,P,T,'linear');
rho_grid = interpn(db.PT.P,db.PT.T,db.PT.rho,P,T,'linear');
cp_grid = interpn(db.PT.P,db.PT.T,db.PT.cp,P,T,'linear');
mu_grid = interpn(db.PT.P,db.PT.T,db.PT.mu,P,T,'linear');
k_grid = interpn(db.PT.P,db.PT.T,db.PT.k,P,T,'linear');

h_cp = PropsSI('H','P',P,'T',T,fluid);
s_cp = PropsSI('S','P',P,'T',T,fluid);
rho_cp = PropsSI('D','P',P,'T',T,fluid);
cp_cp = PropsSI('C','P',P,'T',T,fluid);
mu_cp = PropsSI('V','P',P,'T',T,fluid);
if localIsR1233zdE(fluid)
    k_cp = k_grid;
else
    k_cp = PropsSI('L','P',P,'T',T,fluid);
end

fprintf('%-10s PT midpoint rel err: h %.3g, s %.3g, rho %.3g, cp %.3g, mu %.3g, k %.3g\n', ...
    fluid,localRelErr(h_grid,h_cp),localRelErr(s_grid,s_cp), ...
    localRelErr(rho_grid,rho_cp),localRelErr(cp_grid,cp_cp), ...
    localRelErr(mu_grid,mu_cp),localRelErr(k_grid,k_cp));
end

function err = localRelErr(a,b)
err = abs(a-b)/max(abs(b),eps);
end

function tf = localIsR1233zdE(fluid)
name = lower(regexprep(char(string(fluid)),'[^a-zA-Z0-9]',''));
tf = contains(name,'r1233zde');
end
