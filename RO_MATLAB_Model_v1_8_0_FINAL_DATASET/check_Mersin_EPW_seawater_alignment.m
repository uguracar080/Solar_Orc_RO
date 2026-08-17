function report = check_Mersin_EPW_seawater_alignment(epw_file, seawater_csv) % Mersin EPW ve 8760-hour seawater profile hour indexing uyumunu kontrol eder.

%% SEAWATER PROFILE % CSV time-index ve TMY_EPW_Hour kolonlarini okur.

S = readtable(seawater_csv); % Seawater profile CSV dosyasini okur.
if height(S) ~= 8760 % Seawater profile tam yil satir sayisini kontrol eder.
    error('Seawater profile 8760 row olmali.'); % Eksik/fazla saat varsa kontrolu durdurur.
end % Seawater row-count kosulunu sonlandirir.

%% EPW HEADER VE DATA % EnergyPlus weather file header sonrasi 8760 data satirini okur.

fid = fopen(epw_file, 'r'); % EPW dosyasini text okuma modunda acar.
if fid < 0 % EPW file acilamadiysa kontrol eder.
    error('EPW dosyasi acilamadi: %s', epw_file); % File path probleminde acik hata verir.
end % EPW-open kosulunu sonlandirir.
cleanup = onCleanup(@() fclose(fid)); % Fonksiyon herhangi bir yerde sonlansa bile file handle'i kapatir.
location_line = fgetl(fid); % EPW LOCATION header satirini okur.
for i = 2:8 % Kalan yedi EPW header satirini atlar.
    fgetl(fid); % Mevcut header satirini okur ve kullanmadan gecer.
end % EPW header-skip dongusunu sonlandirir.

C = textscan(fid, '%f%f%f%f%f%[^\n]', 'Delimiter', ','); % Her EPW data row icin ilk bes numeric calendar alanini ve kalan satiri okur.
Year = C{1}; % EPW source year vectorunu alir.
Month = C{2}; % EPW month vectorunu alir.
Day = C{3}; % EPW day vectorunu alir.
HourEPW = C{4}; % EPW 1-24 hour convention vectorunu alir.

%% ALIGNMENT KONTROLLERI % CSV Hour_Start=0-23 ile EPW Hour=1-24 mapping'ini ve calendar alanlarini test eder.

row_count_ok = numel(HourEPW) == 8760; % EPW data row sayisinin 8760 olup olmadigini kontrol eder.
hour_ok = row_count_ok && all(S.TMY_EPW_Hour(:) == HourEPW(:)); % CSV'deki explicit TMY_EPW_Hour kolonunu EPW hour vectoru ile karsilastirir.
month_ok = row_count_ok && all(S.Month(:) == Month(:)); % CSV month values ile EPW month values degerlerini karsilastirir.
day_ok = row_count_ok && all(S.Day(:) == Day(:)); % CSV day values ile EPW day values degerlerini karsilastirir.
source_year_ok = row_count_ok && all(S.TMY_SourceYear(:) == Year(:)); % CSV TMY source-year degerleri ile EPW source-year degerlerini karsilastirir.
hour_start_ok = all(S.Hour_Start(:) == mod(S.TMY_EPW_Hour(:) - 1, 24)); % CSV Hour_Start=0-23 mapping'inin EPW 1-24 convention ile uyumunu kontrol eder.

%% REPORT % Location header ve tum boolean alignment sonuclarini struct olarak dondurur.

report.location_header = string(location_line); % EPW LOCATION satirini traceability icin kaydeder.
report.row_count_ok = row_count_ok; % EPW row-count kontrol sonucunu kaydeder.
report.hour_ok = hour_ok; % EPW-hour mapping kontrol sonucunu kaydeder.
report.hour_start_ok = hour_start_ok; % CSV Hour_Start mapping kontrol sonucunu kaydeder.
report.month_ok = month_ok; % Month alignment kontrol sonucunu kaydeder.
report.day_ok = day_ok; % Day alignment kontrol sonucunu kaydeder.
report.source_year_ok = source_year_ok; % TMY source-year alignment kontrol sonucunu kaydeder.
report.all_ok = row_count_ok && hour_ok && hour_start_ok && month_ok && day_ok && source_year_ok; % Tum alignment kontrollerinden overall flag olusturur.

fprintf('EPW location: %s\n', location_line); % EPW location header satirini Command Window'da gosterir.
fprintf('8760 row        : %d\n', row_count_ok); % Row-count kontrolunu yazdirir.
fprintf('Hour mapping    : %d\n', hour_ok && hour_start_ok); % Hour-index alignment kontrolunu yazdirir.
fprintf('Month/day       : %d\n', month_ok && day_ok); % Calendar alignment kontrolunu yazdirir.
fprintf('TMY source year : %d\n', source_year_ok); % Source-year alignment kontrolunu yazdirir.
fprintf('Overall         : %d\n', report.all_ok); % Overall alignment sonucunu yazdirir.

end % EPW-seawater alignment check fonksiyonunu sonlandirir.
