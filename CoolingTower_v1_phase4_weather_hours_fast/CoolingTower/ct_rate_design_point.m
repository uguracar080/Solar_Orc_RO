function CTDesign = ct_rate_design_point(CTRatingInput, CTConfig)
% CT_RATE_DESIGN_POINT  Build a fixed/rated cooling-tower design structure.
%
% Required / optional CTRatingInput fields:
%   Q_rated_W             [W]        optional; default CTConfig.rating.Q_rated_W
%   T_db_rated_C          [degC]     optional
%   T_wb_rated_C          [degC]     optional
%   P_atm_rated_Pa        [Pa]       optional
%   approach_rated_C      [degC]     optional
%   range_rated_C         [degC]     optional
%   mdot_water_rated      [kg/s]     optional; if absent, Q/(cp*range)
%   mdot_air_rated        [kg_da/s]  optional
%   L_over_G_rated        [-]        optional; if mdot_air absent, used to compute it
%   W_fan_rated_W         [W]        optional; if absent, hp/RT estimate
%
% Output CTDesign fields are component-scoped and ready for annual off-design.

if nargin < 1 || isempty(CTRatingInput)
    CTRatingInput = struct();
end
if nargin < 2 || isempty(CTConfig)
    CTConfig = ct_default_config();
end

Q_rated_W        = getfield_default(CTRatingInput,'Q_rated_W',CTConfig.rating.Q_rated_W);
T_db_rated_C     = getfield_default(CTRatingInput,'T_db_rated_C',CTConfig.rating.T_db_rated_C);
T_wb_rated_C     = getfield_default(CTRatingInput,'T_wb_rated_C',CTConfig.rating.T_wb_rated_C);
P_atm_rated_Pa   = getfield_default(CTRatingInput,'P_atm_rated_Pa',CTConfig.rating.P_atm_rated_Pa);
approach_rated_C = getfield_default(CTRatingInput,'approach_rated_C',CTConfig.rating.approach_rated_C);
range_rated_C    = getfield_default(CTRatingInput,'range_rated_C',CTConfig.rating.range_rated_C);

validate_positive(Q_rated_W,'CTRatingInput.Q_rated_W');
validate_positive(range_rated_C,'CTRatingInput.range_rated_C');
validate_positive(approach_rated_C,'CTRatingInput.approach_rated_C');

T_w_out_rated_C = T_wb_rated_C + approach_rated_C;
T_w_in_rated_C  = T_w_out_rated_C + range_rated_C;
waterRated = ct_water_properties(0.5*(T_w_in_rated_C + T_w_out_rated_C),CTConfig);
cp = waterRated.cp_JkgK;

if isfield(CTRatingInput,'mdot_water_rated') && ~isempty(CTRatingInput.mdot_water_rated)
    mdot_water_rated = CTRatingInput.mdot_water_rated;
else
    mdot_water_rated = Q_rated_W/(cp*range_rated_C);
end
validate_positive(mdot_water_rated,'CTRatingInput.mdot_water_rated');

if isfield(CTRatingInput,'mdot_air_rated') && ~isempty(CTRatingInput.mdot_air_rated)
    mdot_air_rated = CTRatingInput.mdot_air_rated;
    L_over_G_rated = mdot_water_rated/mdot_air_rated;
else
    L_over_G_rated = getfield_default(CTRatingInput,'L_over_G_rated',CTConfig.rating.L_over_G_rated);
    validate_positive(L_over_G_rated,'CTRatingInput.L_over_G_rated');
    mdot_air_rated = mdot_water_rated/L_over_G_rated;
end
validate_positive(mdot_air_rated,'CTRatingInput.mdot_air_rated');

CTAmbientRated = struct();
CTAmbientRated.T_db_C = T_db_rated_C;
CTAmbientRated.T_wb_C = T_wb_rated_C;
CTAmbientRated.P_atm_Pa = P_atm_rated_Pa;

CTMerkelInput = struct();
CTMerkelInput.T_w_in_C = T_w_in_rated_C;
CTMerkelInput.T_w_out_C = T_w_out_rated_C;
CTMerkelInput.mdot_water = mdot_water_rated;
CTMerkelInput.mdot_dry_air = mdot_air_rated;
CTMerkelInput.ambient = CTAmbientRated;
CTMerkelOutput = ct_merkel_number('forward', CTMerkelInput, CTConfig);

if ~CTMerkelOutput.feasible
    error('ct_rate_design_point:MerkelRating', ...
        'Rated point is not feasible. Merkel status: %s', CTMerkelOutput.status);
end

if isfield(CTRatingInput,'W_fan_rated_W') && ~isempty(CTRatingInput.W_fan_rated_W)
    W_fan_rated_W = CTRatingInput.W_fan_rated_W;
else
    Q_rated_kW = Q_rated_W/1000;
    Q_rated_RT = Q_rated_kW/3.517;
    W_fan_rated_W = Q_rated_RT*CTConfig.fan.hp_per_refrigeration_ton*745.7;
end
validate_nonnegative(W_fan_rated_W,'CTRatingInput.W_fan_rated_W');

CTDesign = struct();
CTDesign.component = 'CT';
CTDesign.rating_basis = 'Merkel proper enthalpy-balance rating';
CTDesign.Q_rated_W = Q_rated_W;
CTDesign.Q_rated_kW = Q_rated_W/1000;
CTDesign.Q_rated_RT = CTDesign.Q_rated_kW/3.517;

CTDesign.T_db_rated_C = T_db_rated_C;
CTDesign.T_wb_rated_C = T_wb_rated_C;
CTDesign.P_atm_rated_Pa = P_atm_rated_Pa;
CTDesign.approach_rated_C = approach_rated_C;
CTDesign.range_rated_C = range_rated_C;
CTDesign.T_w_in_rated_C = T_w_in_rated_C;
CTDesign.T_w_out_rated_C = T_w_out_rated_C;

CTDesign.mdot_water_rated = mdot_water_rated;
CTDesign.mdot_air_rated = mdot_air_rated;
CTDesign.L_over_G_rated = L_over_G_rated;
CTDesign.Me_rated = CTMerkelOutput.Me_required;
CTDesign.W_fan_rated_W = W_fan_rated_W;
CTDesign.water_rated = waterRated;

CTDesign.air_rated = CTMerkelOutput.air_in;
CTDesign.merkel_rated = CTMerkelOutput;
CTDesign.transfer_correlation = CTConfig.transfer.correlation;
CTDesign.fan_model = CTConfig.fan.model;
CTDesign.status = 'OK';
end

function val = getfield_default(S, fieldName, defaultVal)
if isfield(S,fieldName) && ~isempty(S.(fieldName))
    val = S.(fieldName);
else
    val = defaultVal;
end
end
function validate_positive(x,name)
if ~isfinite(x) || x <= 0
    error('ct_rate_design_point:InvalidInput','%s must be finite and positive.',name);
end
end
function validate_nonnegative(x,name)
if ~isfinite(x) || x < 0
    error('ct_rate_design_point:InvalidInput','%s must be finite and nonnegative.',name);
end
end
