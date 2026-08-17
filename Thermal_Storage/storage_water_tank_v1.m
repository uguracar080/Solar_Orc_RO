function [StateNext,Out] = storage_water_tank_v1(State,Input,Config)
%STORAGE_WATER_TANK_V1 Simple sensible-water storage placeholder.
%
% The V1 storage model only accepts excess solar heat as charge. It does not
% discharge back to the system yet; that control layer is reserved for PCM or
% storage dispatch integration.

if nargin < 2 || isempty(Input)
    Input = struct();
end
if nargin < 3 || isempty(Config)
    Config = struct();
end
Config = localDefaults(Config);
if nargin < 1 || isempty(State)
    State = localInitialState(Config);
end
Out = localBlankOut(State);

if ~Config.enabled
    Qreq = max(0,localGet(Input,'Q_charge_request_W',0));
    dt = max(0,localGet(Input,'dt_s',0));
    Out.Q_charge_request_W = Qreq;
    Out.Q_charge_W = 0;
    Out.Q_curtailed_W = Qreq;
    Out.E_charge_kWh = 0;
    Out.E_curtailed_kWh = Qreq*dt/3.6e6;
    Out.status = 'DISABLED';
    StateNext = State;
    return
end

Qreq = max(0,localGet(Input,'Q_charge_request_W',0));
dt = max(0,localGet(Input,'dt_s',0));
Ereq = Qreq*dt;
capacityLeft = max(0,State.E_max_J - State.E_J);
Echarge = min(Ereq,capacityLeft);
Ecurtailed = max(0,Ereq - Echarge);

StateNext = State;
StateNext.E_J = min(State.E_max_J,State.E_J + Echarge);
StateNext.SOC = localSafeDivide(StateNext.E_J,State.E_max_J);
StateNext.T_C = Config.T_min_C + StateNext.SOC*(Config.T_max_C - Config.T_min_C);

Out.Q_charge_request_W = Qreq;
Out.Q_charge_W = localSafeDivide(Echarge,dt);
Out.Q_curtailed_W = localSafeDivide(Ecurtailed,dt);
Out.E_charge_kWh = Echarge/3.6e6;
Out.E_curtailed_kWh = Ecurtailed/3.6e6;
Out.SOC = StateNext.SOC;
Out.T_C = StateNext.T_C;
Out.E_stored_kWh = StateNext.E_J/3.6e6;
if Qreq <= 0
    Out.status = 'IDLE';
elseif Ecurtailed > 0
    Out.status = 'FULL_CURTAILED';
else
    Out.status = 'CHARGING';
end
end

function Config = localDefaults(Config)
Config = localSetDefault(Config,'enabled',true);
Config = localSetDefault(Config,'type','water_tank_v1');
Config = localSetDefault(Config,'volume_m3',10.0);
Config = localSetDefault(Config,'T_initial_C',30.0);
Config = localSetDefault(Config,'T_min_C',25.0);
Config = localSetDefault(Config,'T_max_C',95.0);
Config = localSetDefault(Config,'rho_kgm3',997.0);
Config = localSetDefault(Config,'cp_JkgK',4180.0);
end

function State = localInitialState(Config)
Config = localDefaults(Config);
capacity_J = max(0,Config.volume_m3*Config.rho_kgm3*Config.cp_JkgK* ...
    max(0,Config.T_max_C - Config.T_min_C));
T0 = min(max(Config.T_initial_C,Config.T_min_C),Config.T_max_C);
SOC0 = localSafeDivide(T0 - Config.T_min_C,max(Config.T_max_C - Config.T_min_C,eps));
State = struct();
State.E_max_J = capacity_J;
State.E_J = min(max(0,SOC0*capacity_J),capacity_J);
State.SOC = localSafeDivide(State.E_J,capacity_J);
State.T_C = Config.T_min_C + State.SOC*(Config.T_max_C - Config.T_min_C);
end

function Out = localBlankOut(State)
Out = struct();
Out.Q_charge_request_W = 0;
Out.Q_charge_W = 0;
Out.Q_curtailed_W = 0;
Out.E_charge_kWh = 0;
Out.E_curtailed_kWh = 0;
Out.SOC = localGet(State,'SOC',NaN);
Out.T_C = localGet(State,'T_C',NaN);
Out.E_stored_kWh = localGet(State,'E_J',NaN)/3.6e6;
Out.status = 'IDLE';
end

function value = localSafeDivide(num,den)
if isfinite(den) && abs(den) > eps
    value = num/den;
else
    value = 0;
end
end

function value = localGet(S,fieldName,defaultValue)
if isstruct(S) && isfield(S,fieldName) && ~isempty(S.(fieldName))
    value = S.(fieldName);
else
    value = defaultValue;
end
end

function S = localSetDefault(S,fieldName,defaultValue)
if ~isfield(S,fieldName) || isempty(S.(fieldName))
    S.(fieldName) = defaultValue;
end
end
