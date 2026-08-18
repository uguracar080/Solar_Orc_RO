function orcCheck = orc_sthe_core_check(config)
% ORC_STHE_CORE_CHECK Run basic STHE geometry/correlation sanity checks.
%
% This is not a literature validation. It only checks that the physical
% kernels return finite and plausible values for a representative ORC point.

% =========================================================================
% CONFIGURATION
% =========================================================================
if nargin < 1 || isempty(config)
    config = struct();
end
config = orc_default_config(config);

% =========================================================================
% REPRESENTATIVE ORC DESIGN POINT
% =========================================================================
orcFluid = config.orc_fluid;
orcPevap = 10.7e5;                                    % evaporator pressure [Pa]
orcPcond = 1.2e5;                                     % condenser pressure [Pa]
orcMdot = 7.2;                                        % working-fluid flow [kg/s]

% =========================================================================
% EVAPORATOR GEOMETRY
% =========================================================================
orcGeomEvap = orc_sthe_geometry('evaporator',300,4.0,config);

% =========================================================================
% TUBE-SIDE HOT STREAM CHECK
% =========================================================================
orcHotStream = struct();
orcHotStream.fluid = 'Water';                         % temporary test fluid [-]

orcThtf = 433.15;                                     % bulk temperature [K]
orcPhtf = 3.0e5;                                      % bulk pressure [Pa]

orcTubeFlow = struct();
orcTubeFlow.mdot = 20.0;                              % [kg/s]
orcTubeFlow.rho = orc_stream_properties(config,orcHotStream,'D','T',orcThtf,'P',orcPhtf); % [kg/m3]
orcTubeFlow.mu = orc_stream_properties(config,orcHotStream,'V','T',orcThtf,'P',orcPhtf);  % [Pa s]
orcTubeFlow.k = orc_stream_properties(config,orcHotStream,'L','T',orcThtf,'P',orcPhtf);   % [W/m/K]
orcTubeFlow.cp = orc_stream_properties(config,orcHotStream,'C','T',orcThtf,'P',orcPhtf);  % [J/kg/K]

orcTubeCheck = orc_sthe_tube_singlephase(orcTubeFlow,orcGeomEvap,1.0);

% =========================================================================
% SHELL-SIDE LIQUID CHECK
% =========================================================================
orcHsatL = orc_properties(config,'H','P',orcPevap,'Q',0,orcFluid); % [J/kg]
orcHpump = orc_properties(config,'H','P',orcPevap,'T',310.0,orcFluid); % [J/kg]
orcHmid = 0.5*(orcHpump+orcHsatL);                     % [J/kg]

orcShellFlow = struct();
orcShellFlow.mdot = orcMdot;                          % [kg/s]
orcShellFlow.rho = orc_properties(config,'D','P',orcPevap,'H',orcHmid,orcFluid); % [kg/m3]
orcShellFlow.mu = orc_properties(config,'V','P',orcPevap,'H',orcHmid,orcFluid);  % [Pa s]
orcShellFlow.k = orc_properties(config,'L','P',orcPevap,'H',orcHmid,orcFluid);   % [W/m/K]
orcShellFlow.cp = orc_properties(config,'C','P',orcPevap,'H',orcHmid,orcFluid);  % [J/kg/K]

orcShellCheck = orc_sthe_shell_singlephase(orcShellFlow,orcGeomEvap,config);

% =========================================================================
% BOILING CHECK
% =========================================================================
orcBoilInput = struct();
orcBoilInput.q_flux = 1.0e4;                          % [W/m2]
orcBoilInput.P = orcPevap;                            % [Pa]
orcBoilInput.Pcrit = orc_properties(config,'PCRIT',orcFluid); % [Pa]

orcBoilCheck = orc_sthe_boiling(orcBoilInput,orcGeomEvap,config);

% =========================================================================
% TWO-PHASE SHELL PRESSURE-DROP CHECK
% =========================================================================
orc2phFlow = struct();
orc2phFlow.mdot = orcMdot;                            % [kg/s]
orc2phFlow.P = orcPevap;                              % [Pa]
orc2phFlow.rho_l = orc_properties(config,'D','P',orcPevap,'Q',0,orcFluid); % [kg/m3]
orc2phFlow.rho_v = orc_properties(config,'D','P',orcPevap,'Q',1,orcFluid); % [kg/m3]
orc2phFlow.mu_l = orc_properties(config,'V','P',orcPevap,'Q',0,orcFluid);  % [Pa s]
orc2phFlow.mu_v = orc_properties(config,'V','P',orcPevap,'Q',1,orcFluid);  % [Pa s]
orc2phFlow.k_l = orc_properties(config,'L','P',orcPevap,'Q',0,orcFluid);   % [W/m/K]
orc2phFlow.k_v = orc_properties(config,'L','P',orcPevap,'Q',1,orcFluid);   % [W/m/K]
orc2phFlow.cp_l = 1000;                              % dP-only fallback [J/kg/K]
orc2phFlow.cp_v = 1000;                              % dP-only fallback [J/kg/K]
orc2phFlow.x_in = 0;                                  % [-]
orc2phFlow.x_out = 1;                                 % [-]
orc2phFlow.areaFraction = 0.60;                       % test fraction [-]
orc2phFlow.mode = 'evaporation';                      % [-]

orcTwoPhaseDpCheck = orc_sthe_shell_twophase_dp(orc2phFlow,orcGeomEvap,config);

% =========================================================================
% NIST R1233ZD(E) THERMAL-CONDUCTIVITY CHECK
% =========================================================================
orcKTest = struct();
orcKTest.T = [300.0; 300.0; 300.0; 445.0; 445.0];      % [K]
orcKTest.rho = [0.0; 5.4411; 1308.8; 0.0; 168.52];    % [kg/m3]
orcKTest.k_ref = [0.010659; 0.010766; 0.091399; ...
                  0.021758; 0.023992];                % no critical term [W/m/K]
orcKTest.k_model = orc_r1233zde_thermal_conductivity( ...
    config,orcKTest.T,orcKTest.rho);                   % [W/m/K]
orcKTest.err_rel = abs(orcKTest.k_model-orcKTest.k_ref)./orcKTest.k_ref; % [-]
orcKTest.max_err_rel = max(orcKTest.err_rel);          % [-]

% =========================================================================
% CONDENSATION CHECK
% =========================================================================
orcGeomCond = orc_sthe_geometry('condenser',600,8.0,config);

orcTsat = orc_properties(config,'T','P',orcPcond,'Q',0,orcFluid); % [K]
orcHf = orc_properties(config,'H','P',orcPcond,'Q',0,orcFluid);   % [J/kg]
orcHg = orc_properties(config,'H','P',orcPcond,'Q',1,orcFluid);   % [J/kg]

orcCondInput = struct();
orcCondInput.rho_l = orc_properties(config,'D','P',orcPcond,'Q',0,orcFluid); % [kg/m3]
orcCondInput.rho_v = orc_properties(config,'D','P',orcPcond,'Q',1,orcFluid); % [kg/m3]
orcCondInput.mu_l = orc_properties(config,'V','P',orcPcond,'Q',0,orcFluid);  % [Pa s]
orcCondInput.k_l = orc_properties(config,'L','P',orcPcond,'Q',0,orcFluid);   % NIST fallback [W/m/K]
orcCondInput.h_fg = orcHg-orcHf;                      % [J/kg]
orcCondInput.T_sat = orcTsat;                         % [K]
orcCondInput.T_wall = orcTsat-5.0;                    % [K]

orcCondCheck = orc_sthe_condensation(orcCondInput,orcGeomCond,config);

% =========================================================================
% BASIC FINITE CHECKS
% =========================================================================
orcFinite = all(isfinite([ ...
    orcGeomEvap.Dshell,orcGeomCond.Dshell, ...
    orcTubeCheck.h,orcTubeCheck.dp, ...
    orcShellCheck.h,orcShellCheck.dp, ...
    orcBoilCheck.h,orcCondCheck.h,orcTwoPhaseDpCheck.dp]));

% =========================================================================
% OUTPUT STRUCT
% =========================================================================
orcCheck = struct();
orcCheck.orc_geometry_evap = orcGeomEvap;
orcCheck.orc_geometry_cond = orcGeomCond;
orcCheck.orc_tube_singlephase = orcTubeCheck;
orcCheck.orc_shell_singlephase = orcShellCheck;
orcCheck.orc_boiling = orcBoilCheck;
orcCheck.orc_shell_twophase_dp = orcTwoPhaseDpCheck;
orcCheck.orc_condensation = orcCondCheck;
orcCheck.orc_k_nist_test = orcKTest;
orcCheck.orc_allFinite = orcFinite;

% =========================================================================
% COMMAND-WINDOW SUMMARY
% =========================================================================
fprintf('\n============================================================\n');
fprintf('ORC STHE CORE CHECK - V%s\n',config.orc_modelVersion);
fprintf('============================================================\n');
fprintf('Evap shell diameter : %8.4f m\n',orcGeomEvap.Dshell);
fprintf('Cond shell diameter : %8.4f m\n',orcGeomCond.Dshell);
fprintf('Tube-side HTC       : %8.2f W/m2-K\n',orcTubeCheck.h);
fprintf('Shell single HTC    : %8.2f W/m2-K\n',orcShellCheck.h);
fprintf('Boiling HTC         : %8.2f W/m2-K\n',orcBoilCheck.h);
fprintf('Condensation HTC    : %8.2f W/m2-K\n',orcCondCheck.h);
fprintf('R1233zdE k test max : %8.4f %%\n',100*orcKTest.max_err_rel);
fprintf('Shell single dP     : %8.2f Pa\n',orcShellCheck.dp);
fprintf('Shell 2ph dP        : %8.2f Pa\n',orcTwoPhaseDpCheck.dp);
fprintf('All finite          : %d\n',orcFinite);
fprintf('============================================================\n');

end
