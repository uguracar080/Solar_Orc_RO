function [PriorX, PriorY, PriorSource] = ro_build_guided_prior(envelope_csv, probes_csv, pilot_csv) % Envelope probe logu ve varsa basarili guided pilotu birlestirerek final DOE proposal prior'ini olusturur.

%% GIRDI DOSYALARI % Varsayilan dosya adlarini tamamlar ve gerekli dosyalari kontrol eder.
if nargin < 1 || strlength(string(envelope_csv)) == 0 % Envelope CSV path'i verilmemisse kontrol eder.
    envelope_csv = 'RO_feasibility_envelope.csv'; % Varsayilan state-level envelope dosya adini tanimlar.
end % Envelope-path default kontrolunu sonlandirir.
if nargin < 2 || strlength(string(probes_csv)) == 0 % Probe CSV path'i verilmemisse kontrol eder.
    probes_csv = 'RO_feasibility_envelope_probes.csv'; % Varsayilan probe-log dosya adini tanimlar.
end % Probe-path default kontrolunu sonlandirir.
if nargin < 3 || strlength(string(pilot_csv)) == 0 % Guided pilot CSV path'i verilmemisse kontrol eder.
    pilot_csv = 'RO_ANN_probe_guided_pilot.csv'; % Basarili 120-point pilot dosyasini varsayilan additional prior yapar.
end % Pilot-path default kontrolunu sonlandirir.
if ~isfile(envelope_csv) || ~isfile(probes_csv) % Envelope veya probe log eksikse kontrol eder.
    error('Final guided DOE icin %s ve %s dosyalari Current Folder icinde bulunmalidir.', envelope_csv, probes_csv); % Eksik zorunlu prior dosyalarini bildirir.
end % Zorunlu prior file kontrolunu sonlandirir.

%% ENVELOPE PROBE PRIOR % 622 recovery probe'unu parent Qf-T-Cf state bilgileriyle birlestirir.
Envelope = readtable(envelope_csv, 'TextType', 'string'); % State-level envelope tablosunu okur.
Probe = readtable(probes_csv, 'TextType', 'string'); % Recovery-level probe tablosunu okur.
[tf, loc] = ismember(Probe.State_ID, Envelope.State_ID); % Her probe'un parent envelope state row'unu bulur.
if ~all(tf) % Parent state'i bulunamayan probe varsa kontrol eder.
    error('Probe log icindeki bazi State_ID degerleri envelope CSV ile eslesmedi.'); % Prior veri tutarsizligini bildirir.
end % Parent-state consistency kontrolunu sonlandirir.
PriorX = [Envelope.Qf_train_m3h(loc), Envelope.T_RO_in_C(loc), Envelope.Cf_kg_m3(loc), Probe.R_target]; % Probe prior [Qf,T,Cf,R] input matrixini olusturur.
PriorY = double(Probe.DatasetValid); % Probe truth-valid flag'lerini binary proposal label'i olarak alir.
PriorSource = repmat("EnvelopeProbe", height(Probe), 1); % Her probe row'unun kaynagini diagnostic icin etiketler.

%% GUIDED PILOT PRIOR % 90.8% valid-rate veren 120-point pilotu ek evidence olarak proposal prior'ina ekler.
if isfile(pilot_csv) % Basarili guided-pilot truth dataset dosyasi mevcutsa kontrol eder.
    Pilot = readtable(pilot_csv, 'TextType', 'string'); % Pilot truth datasetini okur.
    required = {'Qf_train_m3h','T_RO_in_C','Cf_kg_m3','R_target','DatasetValid'}; % Pilot prior icin gerekli kolon isimlerini tanimlar.
    if all(ismember(required, Pilot.Properties.VariableNames)) % Tum gerekli kolonlar varsa kontrol eder.
        Xp = [Pilot.Qf_train_m3h, Pilot.T_RO_in_C, Pilot.Cf_kg_m3, Pilot.R_target]; % Pilot [Qf,T,Cf,R] input matrixini olusturur.
        Yp = double(Pilot.DatasetValid); % Pilot truth-valid label vectorunu alir.
        PriorX = [PriorX; Xp]; %#ok<AGROW> % Pilot inputlarini envelope-probe prior'ina ekler.
        PriorY = [PriorY; Yp]; %#ok<AGROW> % Pilot label'larini prior label vectorune ekler.
        PriorSource = [PriorSource; repmat("GuidedPilot", height(Pilot), 1)]; %#ok<AGROW> % Pilot source label'larini ekler.
    else % Pilot CSV mevcut fakat gerekli kolonlardan biri eksikse bu dali kullanir.
        warning('Pilot CSV bulundu ancak gerekli kolonlar eksik; final proposal prior yalnizca envelope probe logunu kullanacak.'); % Pilot prior'in neden kullanilmadigini bildirir.
    end % Pilot-column kontrolunu sonlandirir.
else % Pilot CSV mevcut degilse bu dali kullanir.
    warning('RO_ANN_probe_guided_pilot.csv bulunamadi; final proposal prior yalnizca envelope probe logunu kullanacak.'); % Additional prior eksikligini bildirir.
end % Pilot-file existence kontrolunu sonlandirir.

%% FINITE FILTER % NaN/Inf input veya label satirlarini proposal prior'dan cikarir.
finite_mask = all(isfinite(double(PriorX)), 2) & isfinite(double(PriorY)); % Tum dort input ve label'i finite olan satirlari belirler.
PriorX = double(PriorX(finite_mask, :)); % Prior input matrixini finite satirlara indirger.
PriorY = double(PriorY(finite_mask)); % Prior label vectorunu ayni mask ile filtreler.
PriorSource = PriorSource(finite_mask); % Prior source label'larini ayni mask ile filtreler.

end % Final guided prior builder fonksiyonunu sonlandirir.
