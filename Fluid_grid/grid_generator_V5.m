function thermoDB = grid_generator_V5(opts)
% GRID_GENERATOR_V5 Generate an offline CoolProp-backed property database.
%
% Default use creates a full R1233zd(E) database:
%   grid_generator_V5
%
% Small custom run:
%   opts = struct('Np',20,'Nh',20,'Ns',20,'Nt',20,'Nsat',20, ...
%       'fileSuffix','SMALL','showProgress',true);
%   grid_generator_V5(opts)
%
% V5 schema adds transport properties, quality maps and a (P,T) grid so
% later ORC property calls can be served without runtime CoolProp calls.

if nargin < 1 || isempty(opts)
    opts = struct();
end

opts = localDefaults(opts);
tStart = tic;

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end
addpath(scriptDir);

if exist('PropsSI','file') ~= 2 && exist('PropsSI','builtin') ~= 5
    error('grid_generator_V5:PropsSIMissing', ...
        ['PropsSI.m is not on the MATLAB path. Add the supplied wrapper ', ...
         'and configure Python CoolProp before running this generator.']);
end

fluid = strtrim(opts.fluid);
fprintf('\nV5 property database generation started: %s\n',datestr(datetime('now')));
fprintf('Fluid: %s\n',fluid);

meta = localReadMeta(fluid);

P_vec = linspace(opts.Pmin_bar*1e5,opts.Pmax_bar*1e5,opts.Np);
s_vec = linspace(opts.smin,opts.smax,opts.Ns);
h_vec = linspace(opts.hmin,opts.hmax,opts.Nh);
T_vec = linspace(opts.Tmin_K,opts.Tmax_K,opts.Nt);

P_sat_max = min(opts.Pmax_bar*1e5,opts.satPressureFractionOfCritical*meta.Pcrit);
P_sat_vec = linspace(opts.Pmin_bar*1e5,P_sat_max,opts.Nsat);

fprintf('P range     : %.4g to %.4g bar (%d)\n',P_vec(1)/1e5,P_vec(end)/1e5,numel(P_vec));
fprintf('h range     : %.4g to %.4g kJ/kg (%d)\n',h_vec(1)/1e3,h_vec(end)/1e3,numel(h_vec));
fprintf('s range     : %.4g to %.4g J/kg/K (%d)\n',s_vec(1),s_vec(end),numel(s_vec));
fprintf('T range     : %.4g to %.4g K (%d)\n',T_vec(1),T_vec(end),numel(T_vec));
fprintf('sat P range : %.4g to %.4g bar (%d)\n',P_sat_vec(1)/1e5,P_sat_vec(end)/1e5,numel(P_sat_vec));

% -------------------------------------------------------------------------
% GRID 1: (P,s)
% -------------------------------------------------------------------------
Ps = struct();
Ps.P = P_vec;
Ps.s = s_vec;
Ps.H = nan(opts.Np,opts.Ns);
Ps.T = nan(opts.Np,opts.Ns);
Ps.rho = nan(opts.Np,opts.Ns);
Ps.cp = nan(opts.Np,opts.Ns);
Ps.mu = nan(opts.Np,opts.Ns);
Ps.k = nan(opts.Np,opts.Ns);

for i = 1:opts.Np
    P = P_vec(i);
    Ps.H(i,:) = localPropsVector('H','P',P,'S',s_vec,fluid);
    Ps.T(i,:) = localPropsVector('T','P',P,'S',s_vec,fluid);
    Ps.rho(i,:) = localPropsVector('D','P',P,'S',s_vec,fluid);
    Ps.cp(i,:) = localPropsVector('C','P',P,'S',s_vec,fluid);
    Ps.mu(i,:) = localPropsVector('V','P',P,'S',s_vec,fluid);
    Ps.k(i,:) = localConductivityVector(fluid,Ps.T(i,:),Ps.rho(i,:), ...
        'P',P,'S',s_vec);
    localProgress(opts,'GRID Ps',i,opts.Np);
end

% -------------------------------------------------------------------------
% GRID 2: (P,h)
% -------------------------------------------------------------------------
Ph = struct();
Ph.P = P_vec;
Ph.h = h_vec;
Ph.T = nan(opts.Np,opts.Nh);
Ph.s = nan(opts.Np,opts.Nh);
Ph.rho = nan(opts.Np,opts.Nh);
Ph.cp = nan(opts.Np,opts.Nh);
Ph.mu = nan(opts.Np,opts.Nh);
Ph.k = nan(opts.Np,opts.Nh);

for i = 1:opts.Np
    P = P_vec(i);
    Ph.T(i,:) = localPropsVector('T','P',P,'H',h_vec,fluid);
    Ph.s(i,:) = localPropsVector('S','P',P,'H',h_vec,fluid);
    Ph.rho(i,:) = localPropsVector('D','P',P,'H',h_vec,fluid);
    Ph.cp(i,:) = localPropsVector('C','P',P,'H',h_vec,fluid);
    Ph.mu(i,:) = localPropsVector('V','P',P,'H',h_vec,fluid);
    Ph.k(i,:) = localConductivityVector(fluid,Ph.T(i,:),Ph.rho(i,:), ...
        'P',P,'H',h_vec);
    localProgress(opts,'GRID Ph',i,opts.Np);
end

% -------------------------------------------------------------------------
% GRID 3: (P,T)
% -------------------------------------------------------------------------
PT = struct();
PT.P = P_vec;
PT.T = T_vec;
PT.H = nan(opts.Np,opts.Nt);
PT.s = nan(opts.Np,opts.Nt);
PT.rho = nan(opts.Np,opts.Nt);
PT.cp = nan(opts.Np,opts.Nt);
PT.mu = nan(opts.Np,opts.Nt);
PT.k = nan(opts.Np,opts.Nt);
PT.Q = nan(opts.Np,opts.Nt);

for i = 1:opts.Np
    P = P_vec(i);
    PT.H(i,:) = localPropsVector('H','P',P,'T',T_vec,fluid);
    PT.s(i,:) = localPropsVector('S','P',P,'T',T_vec,fluid);
    PT.rho(i,:) = localPropsVector('D','P',P,'T',T_vec,fluid);
    PT.cp(i,:) = localPropsVector('C','P',P,'T',T_vec,fluid);
    PT.mu(i,:) = localPropsVector('V','P',P,'T',T_vec,fluid);
    PT.k(i,:) = localConductivityVector(fluid,T_vec,PT.rho(i,:), ...
        'P',P,'T',T_vec);
    PT.Q(i,:) = localCleanQuality(localPropsVector('Q','P',P,'T',T_vec,fluid));
    localProgress(opts,'GRID PT',i,opts.Np);
end

% -------------------------------------------------------------------------
% GRID 4: saturation table
% -------------------------------------------------------------------------
sat = struct();
sat.P = P_sat_vec;
sat.T = localSatVector('T',P_sat_vec,0,fluid);
sat.hf = localSatVector('H',P_sat_vec,0,fluid);
sat.hg = localSatVector('H',P_sat_vec,1,fluid);
sat.sf = localSatVector('S',P_sat_vec,0,fluid);
sat.sg = localSatVector('S',P_sat_vec,1,fluid);
sat.rho_f = localSatVector('D',P_sat_vec,0,fluid);
sat.rho_g = localSatVector('D',P_sat_vec,1,fluid);
sat.cp_f = localSatVector('C',P_sat_vec,0,fluid);
sat.cp_g = localSatVector('C',P_sat_vec,1,fluid);
sat.mu_f = localSatVector('V',P_sat_vec,0,fluid);
sat.mu_g = localSatVector('V',P_sat_vec,1,fluid);
sat.k_f = localConductivityVector(fluid,sat.T,sat.rho_f,'P',P_sat_vec,'Q',0);
sat.k_g = localConductivityVector(fluid,sat.T,sat.rho_g,'P',P_sat_vec,'Q',1);

Ps.Q = localQualityGridFromS(Ps.P,Ps.s,sat);
Ph.Q = localQualityGridFromH(Ph.P,Ph.h,sat);

% -------------------------------------------------------------------------
% GRID 5: isentropic enthalpy helper
% -------------------------------------------------------------------------
iso = struct();
iso.P = P_vec;
iso.s = s_vec;
iso.h2s = Ps.H.';

thermoDB = struct();
thermoDB.schema = 'thermoDB_v5';
thermoDB.fluid = fluid;
thermoDB.meta = meta;
thermoDB.ranges = opts;
thermoDB.sat = sat;
thermoDB.Ps = Ps;
thermoDB.Ph = Ph;
thermoDB.PT = PT;
thermoDB.iso = iso;
thermoDB.qualityConvention = 'Q is NaN for single-phase states and 0..1 inside the saturation dome.';
thermoDB.transportUnits = struct('cp','J/kg/K','mu','Pa*s','k','W/m/K','rho','kg/m3');
thermoDB.createdAt = char(datetime('now','Format','yyyy-MM-dd HH:mm:ss'));

localPrintFiniteSummary(thermoDB);

if opts.saveFile
    outDir = opts.outputDir;
    if isempty(outDir)
        outDir = scriptDir;
    end
    if ~exist(outDir,'dir')
        mkdir(outDir);
    end
    filename = localOutputFilename(outDir,fluid,opts);
    save(filename,'thermoDB','-v7.3');
    fprintf('Saved: %s\n',filename);
end

fprintf('V5 generation finished in %.2f s.\n',toc(tStart));

end

function opts = localDefaults(opts)
opts = localSetDefault(opts,'fluid','R1233zd(E)');
opts = localSetDefault(opts,'Pmin_bar',1.0);
opts = localSetDefault(opts,'Pmax_bar',34.5);
opts = localSetDefault(opts,'smin',1000);
opts = localSetDefault(opts,'smax',1800);
opts = localSetDefault(opts,'hmin',220e3);
opts = localSetDefault(opts,'hmax',490e3);
opts = localSetDefault(opts,'Tmin_K',260);
opts = localSetDefault(opts,'Tmax_K',430);
opts = localSetDefault(opts,'Np',1000);
opts = localSetDefault(opts,'Ns',1000);
opts = localSetDefault(opts,'Nh',1000);
opts = localSetDefault(opts,'Nt',1000);
opts = localSetDefault(opts,'Nsat',1000);
opts = localSetDefault(opts,'satPressureFractionOfCritical',0.99);
opts = localSetDefault(opts,'showProgress',true);
opts = localSetDefault(opts,'progressEvery',max(1,ceil(opts.Np/20)));
opts = localSetDefault(opts,'saveFile',true);
opts = localSetDefault(opts,'outputDir','');
opts = localSetDefault(opts,'fileSuffix','V5');
end

function opts = localSetDefault(opts,fieldName,defaultValue)
if ~isfield(opts,fieldName) || isempty(opts.(fieldName))
    opts.(fieldName) = defaultValue;
end
end

function meta = localReadMeta(fluid)
meta = struct();
meta.Pcrit = PropsSI('PCRIT',fluid);
meta.Tcrit = PropsSI('TCRIT',fluid);
meta.Tmin = PropsSI('TMIN',fluid);
meta.Tmax = PropsSI('TMAX',fluid);
try
    meta.rhocrit = PropsSI('RHOCRIT',fluid);
catch
    meta.rhocrit = NaN;
end
meta.generator = 'grid_generator_V5';
meta.source = 'CoolProp PropsSI for thermodynamics and transport except R1233zd(E) k';
if localIsR1233zdE(fluid)
    meta.k_model = 'NIST R1233zd(E) background correlation copied into generator';
else
    meta.k_model = 'CoolProp L';
end
end

function row = localPropsVector(outKey,key1,val1,key2,vec2,fluid)
row = nan(1,numel(vec2));
try
    raw = PropsSI(outKey,key1,val1,key2,vec2,fluid);
    row = raw(:).';
catch
    for j = 1:numel(vec2)
        try
            row(j) = PropsSI(outKey,key1,val1,key2,vec2(j),fluid);
        catch
            row(j) = NaN;
        end
    end
end
end

function row = localSatVector(outKey,P_vec,Q,fluid)
row = nan(1,numel(P_vec));
try
    raw = PropsSI(outKey,'P',P_vec,'Q',Q,fluid);
    row = raw(:).';
catch
    for j = 1:numel(P_vec)
        try
            row(j) = PropsSI(outKey,'P',P_vec(j),'Q',Q,fluid);
        catch
            row(j) = NaN;
        end
    end
end
end

function k = localConductivityVector(fluid,T,rho,key1,val1,key2,val2)
if localIsR1233zdE(fluid)
    k = localR1233zdEConductivity(T,rho);
else
    k = localPropsVector('L',key1,val1,key2,val2,fluid);
end
end

function Q = localQualityGridFromH(P_vec,h_vec,sat)
hf = interp1(sat.P,sat.hf,P_vec,'linear',NaN).';
hg = interp1(sat.P,sat.hg,P_vec,'linear',NaN).';
den = hg - hf;
Q = (h_vec - hf)./den;
Q = localCleanQuality(Q);
end

function Q = localQualityGridFromS(P_vec,s_vec,sat)
sf = interp1(sat.P,sat.sf,P_vec,'linear',NaN).';
sg = interp1(sat.P,sat.sg,P_vec,'linear',NaN).';
den = sg - sf;
Q = (s_vec - sf)./den;
Q = localCleanQuality(Q);
end

function Q = localCleanQuality(Q)
Q(~isfinite(Q) | Q < 0 | Q > 1) = NaN;
end

function tf = localIsR1233zdE(fluid)
name = lower(regexprep(char(string(fluid)),'[^a-zA-Z0-9]',''));
tf = contains(name,'r1233zde');
end

function k = localR1233zdEConductivity(T,rho)
Tc = 439.6;
rhoc = 480.239;
A = [-0.140033e-1, 0.378160e-1, -0.245832e-2];
B = [ 0.862816e-2,  0.914709e-3; ...
     -0.208988e-1, -0.407914e-2; ...
      0.511968e-1,  0.845668e-2; ...
     -0.349076e-1, -0.108985e-1; ...
      0.975727e-2,  0.538262e-2; ...
     -0.926484e-3, -0.806009e-3];

Tr = T./Tc;
rhor = rho./rhoc;
k0 = A(1) + A(2).*Tr + A(3).*Tr.^2;
kr = zeros(size(k0));
for i = 1:6
    kr = kr + (B(i,1) + B(i,2).*Tr).*rhor.^i;
end
k = k0 + kr;
k(~isfinite(k) | k <= 0) = NaN;
end

function localProgress(opts,labelText,i,n)
if ~opts.showProgress
    return
end
if i == 1 || i == n || mod(i,opts.progressEvery) == 0
    fprintf('%s: %d/%d (%.1f%%)\n',labelText,i,n,100*i/n);
end
end

function filename = localOutputFilename(outDir,fluid,opts)
cleanFluid = regexprep(fluid,'[\\/:*?"<>|]','_');
suffix = char(string(opts.fileSuffix));
if isempty(suffix)
    fileBase = sprintf('thermoDB_%s.mat',cleanFluid);
else
    fileBase = sprintf('thermoDB_%s_%s.mat',cleanFluid,suffix);
end
filename = fullfile(outDir,fileBase);
end

function localPrintFiniteSummary(db)
fprintf('\nFinite-value summary:\n');
localPrintStructFinite('sat',db.sat);
localPrintStructFinite('Ps',db.Ps);
localPrintStructFinite('Ph',db.Ph);
localPrintStructFinite('PT',db.PT);
end

function localPrintStructFinite(prefix,st)
fields = fieldnames(st);
for i = 1:numel(fields)
    value = st.(fields{i});
    if isnumeric(value) && numel(value) > 1
        fprintf('  %-10s %-8s %.4f\n',prefix,fields{i},nnz(isfinite(value))/numel(value));
    end
end
end
