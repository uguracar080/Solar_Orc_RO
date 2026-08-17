%% ========================================================================
%  SEAWATER PROFILE - TEMPERATURE AND SALINITY PLOTS
%  ========================================================================

clear; clc; close all;                                                % Workspace'i, Command Window'u ve açık figürleri temizler.


%% ========================================================================
%  1. CSV DOSYASINI OKU
%  ========================================================================

fileName = 'seawater_profile.csv';                                    % Okunacak yıllık deniz suyu profil dosyasının adını tanımlar.

opts = detectImportOptions(fileName);                                 % CSV dosyasındaki sütun tiplerini otomatik olarak algılar.

opts.VariableNamingRule = 'preserve';                                 % CSV dosyasındaki orijinal sütun isimlerini değiştirmeden korur.

data = readtable(fileName, opts);                                     % CSV dosyasını MATLAB table formatında okur.


%% ========================================================================
%  2. GEREKLİ VERİLERİ TABLODAN AL
%  ========================================================================

hour = data.("Hour_Index");                                           % 1 ile 8760 arasındaki saat indeksini alır.

T_sea = data.("SeaWater_Temperature_C");                              % Saatlik deniz suyu sıcaklığını [°C] alır.

salinity = data.("Salinity_CMEMS_native");                            % Saatlik Copernicus salinity değerini alır.


%% ========================================================================
%  3. TARİH VE SAAT VERİSİNİ HAZIRLA
%  ========================================================================

dateRaw = data.("Representative_DateTime_Local");                     % CSV dosyasındaki temsili yerel tarih-saat sütununu alır.

if isdatetime(dateRaw)                                                % Tarih-saat sütununun zaten datetime formatında olup olmadığını kontrol eder.

    time = dateRaw;                                                   % Zaten datetime ise doğrudan kullanır.

else                                                                  % Tarih-saat sütunu datetime değilse bu bloğa girer.

    time = datetime(string(dateRaw));                                 % Metin biçimindeki tarih-saat bilgisini MATLAB datetime formatına dönüştürür.

end                                                                   % Tarih-saat kontrolünü tamamlar.


%% ========================================================================
%  4. VERİ UZUNLUĞUNU KONTROL ET
%  ========================================================================

fprintf('\n');                                                        % Command Window'da boş satır bırakır.

fprintf('Toplam veri sayisi : %d saat\n', height(data));              % CSV dosyasındaki toplam saat sayısını ekrana yazdırır.

fprintf('Baslangic zamani   : %s\n', string(time(1)));                % İlk veri noktasının tarih ve saatini ekrana yazdırır.

fprintf('Bitis zamani       : %s\n', string(time(end)));              % Son veri noktasının tarih ve saatini ekrana yazdırır.

fprintf('\n');                                                        % Command Window'da boş satır bırakır.


%% ========================================================================
%  5. SICAKLIK İSTATİSTİKLERİNİ YAZDIR
%  ========================================================================

fprintf('DENIZ SUYU SICAKLIGI\n');                                    % Sıcaklık sonuçları için başlık yazdırır.

fprintf('Minimum  : %.3f °C\n', min(T_sea));                          % Yıllık minimum deniz suyu sıcaklığını hesaplar ve yazdırır.

fprintf('Maximum  : %.3f °C\n', max(T_sea));                          % Yıllık maksimum deniz suyu sıcaklığını hesaplar ve yazdırır.

fprintf('Ortalama : %.3f °C\n', mean(T_sea));                         % Yıllık ortalama deniz suyu sıcaklığını hesaplar ve yazdırır.

fprintf('\n');                                                        % Command Window'da boş satır bırakır.


%% ========================================================================
%  6. SALINITY İSTATİSTİKLERİNİ YAZDIR
%  ========================================================================

fprintf('DENIZ SUYU SALINITY\n');                                     % Salinity sonuçları için başlık yazdırır.

fprintf('Minimum  : %.3f\n', min(salinity));                          % Yıllık minimum salinity değerini hesaplar ve yazdırır.

fprintf('Maximum  : %.3f\n', max(salinity));                          % Yıllık maksimum salinity değerini hesaplar ve yazdırır.

fprintf('Ortalama : %.3f\n', mean(salinity));                         % Yıllık ortalama salinity değerini hesaplar ve yazdırır.

fprintf('\n');                                                        % Command Window'da boş satır bırakır.


%% ========================================================================
%  7. FIGURE 1 - YILLIK DENİZ SUYU SICAKLIĞI
%  ========================================================================

figure;                                                               % Deniz suyu sıcaklığı için yeni bir figure oluşturur.

plot(time, T_sea, 'LineWidth', 1.0);                                 % Saatlik deniz suyu sıcaklığını zamana bağlı olarak çizer.

grid on;                                                              % Grafik üzerine grid çizgilerini ekler.

box on;                                                               % Grafik eksenlerinin çevresine kutu ekler.

xlabel('Time');                                                       % X ekseninin adını belirler.

ylabel('Seawater Temperature (°C)');                                  % Y ekseninin adını ve birimini belirler.

title('Hourly Seawater Temperature Profile');                         % Grafiğin başlığını belirler.

xlim([time(1) time(end)]);                                            % X eksenini yılın başlangıcı ve sonuyla sınırlar.


%% ========================================================================
%  8. FIGURE 2 - YILLIK DENİZ SUYU SALINITY
%  ========================================================================

figure;                                                               % Salinity profili için yeni bir figure oluşturur.

plot(time, salinity, 'LineWidth', 1.0);                               % Saatlik salinity değerlerini zamana bağlı olarak çizer.

grid on;                                                              % Grafik üzerine grid çizgilerini ekler.

box on;                                                               % Grafik eksenlerinin çevresine kutu ekler.

xlabel('Time');                                                       % X ekseninin adını belirler.

ylabel('Salinity');                                                   % Y ekseninin adını belirler.

title('Hourly Seawater Salinity Profile');                            % Grafiğin başlığını belirler.

xlim([time(1) time(end)]);                                            % X eksenini yılın başlangıcı ve sonuyla sınırlar.