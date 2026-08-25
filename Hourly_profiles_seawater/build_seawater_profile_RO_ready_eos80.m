function Profile = build_seawater_profile_RO_ready_eos80(input_csv, output_csv)
%BUILD_SEAWATER_PROFILE_RO_READY_EOS80 Add RO-ready Cf_kg_m3 to seawater CSV.
%
% This is a diagnostic fallback for environments where the TEOS-10 GSW
% toolbox is not available. For publication calculations, prefer
% ro_preprocess_seawater_profile_teos10.m with the official GSW toolbox.

if nargin < 1 || strlength(string(input_csv)) == 0
    input_csv = 'seawater_profile.csv';
end
if nargin < 2 || strlength(string(output_csv)) == 0
    output_csv = 'seawater_profile_RO_ready_EOS80.csv';
end

Profile = readtable(input_csv);
required_columns = {'Hour_Index','SeaWater_Temperature_C','Salinity_CMEMS_native'};
for i = 1:numel(required_columns)
    if ~ismember(required_columns{i}, Profile.Properties.VariableNames)
        error('Input CSV icinde gerekli kolon bulunamadi: %s', required_columns{i});
    end
end
if height(Profile) ~= 8760 || any(Profile.Hour_Index(:) ~= (1:8760).')
    error('Seawater profile 8760 satir ve Hour_Index=1:8760 yapisinda olmali.');
end

SP = double(Profile.Salinity_CMEMS_native);
T = double(Profile.SeaWater_Temperature_C);

% UNESCO 1983 / EOS-80 density of seawater at atmospheric pressure.
rho_w = 999.842594 + 6.793952e-2*T - 9.095290e-3*T.^2 + ...
    1.001685e-4*T.^3 - 1.120083e-6*T.^4 + 6.536332e-9*T.^5;
A = 0.824493 - 4.0899e-3*T + 7.6438e-5*T.^2 - ...
    8.2467e-7*T.^3 + 5.3875e-9*T.^4;
B = -5.72466e-3 + 1.0227e-4*T - 1.6546e-6*T.^2;
C = 4.8314e-4;
rho_kg_m3 = rho_w + A.*SP + B.*SP.^1.5 + C.*SP.^2;

SR_g_kg = (35.16504 / 35.0) .* SP;
Cf_kg_m3 = rho_kg_m3 .* SR_g_kg / 1000.0;

Profile.Reference_Salinity_g_kg = SR_g_kg;
Profile.SeaWater_Density_EOS80_kg_m3 = rho_kg_m3;
Profile.Cf_kg_m3 = Cf_kg_m3;
Profile.Cf_Conversion_Method = repmat("EOS80_atm_SP_to_SR_rho_diagnostic", height(Profile), 1);

writetable(Profile, output_csv);

fprintf('EOS-80 diagnostic conversion tamamlandi.\n');
fprintf('Input SP range : %.6f - %.6f\n', min(SP), max(SP));
fprintf('T range        : %.6f - %.6f C\n', min(T), max(T));
fprintf('Cf range       : %.6f - %.6f kg/m3\n', min(Cf_kg_m3), max(Cf_kg_m3));
fprintf('Cf < 38.5 h    : %d / %d\n', sum(Cf_kg_m3 < 38.5), height(Profile));
fprintf('Output CSV     : %s\n', output_csv);
end
