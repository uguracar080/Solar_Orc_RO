%% PTC_WasteHeat_PTCPreheater_ORC_Pinch_Condenser_UA_Fan_SingleFile.m
% Tek dosya (script + local functions)
% Amaç:
%   (A) Atık ısı (su) kaynağını parametreli tanımla (Kaska 2014 Case-1: 122.4°C, 16.23 kg/s)
%   (B) PTC sahasını (SYLTHERM 800) seri/paralel modül sayısı ile modelle
%   (C) PTC -> Atık su ön ısıtıcı eşanjörünü (counterflow) ε–NTU ile modelle:
%       - Atık su debisi sabit, hedef Tout_waste ver
%       - Hedefe ulaşmak için UA_required çöz
%       - Minimum yaklaşma sıcaklığı (ΔTmin) kontrolü yap
%   (D) Atık su (State-1) -> ORC evaporatörü (pinch point mantığı korunur)
%   (E) ORC çevrimi CoolProp PropsSI wrapper ile çöz (R245fa)
%   (F) Air-cooled condenser: verilen Qcon'u atacak UA_required bul (faz değişimli tarafta Tcond~sabittir)
%   (G) Fan gücü: Yumrutaş (2002) fan işi yaklaşımı + (opsiyonel) hava tarafı Δp modeli
%
% Gereken:
%   - PropsSI.m (CoolProp wrapper)
%   - Optimization Toolbox (fsolve/fzero)
%
% Not:
%   - PTC modülü senin verdiğin local function (ptc_solve_singleModule) ile aynıdır.
%   - PTC saha: seri bağlantıda Tin güncellenir, paralelde akış bölünür/birleşir.
%   - ORC evaporatör pinch çözümü "sende olan" mantıkla korunur; sadece hot-stream artık atık sudur.

clear; clc; close all;                                                            % Ortamı temizle
tStart = tic;                                                                      % Toplam çalışma süresi ölçümü başlat

%% ========================= 1) GENEL AYARLAR =========================
cfg = struct();                                                                    % Genel konfigürasyon
cfg.deltaT_pinch_K   = 7.0;                                                        % ORC evaporatör pinch yaklaşımı [K]
cfg.deltaTmin_HX_K   = 7.0;                                                        % PTC->Atık su HX minimum yaklaşma [K]
cfg.make_plots       = false;                                                       % Figür üret
cfg.show_tables      = true;                                                        % Sonuç tablolarını yazdır
cfg.verbose          = true;                                                        % Detay yazdır
cfg.use_HX_preheat   = false;                                                       % true: PTC->Waste HX aktif, false: bypass (no preheat)
cfg.orc_design_mode = 'kaska_totalQ';                                               % 'pinch_only' (eski) | 'kaska_totalQ' (yeni)
cfg.max_iter_orc    = 60;                                                           % iter limiti
cfg.tol_Tout_K      = 1e-4;                                                         % Tout yakınsama toleransı [K]
cfg.tol_pinch_K     = 1e-3;                                                         % pinch toleransı [K] (opsiyonel kontrol)



cfg.N_int            = 25;                                                         % (HIZ) Integral noktası (80 yerine 25 genelde yeterli)
cfg.use_cpLUT        = true;                                                       % (HIZ) Su cp(T) LUT kullan (PropsSI çağrılarını azaltır)

opts = optimoptions('fsolve','Display','none', ...                                 % fsolve sessiz
    'FunctionTolerance',1e-10,'StepTolerance',1e-10);                              % toleranslar

%% ========================= 2) ATIK ISI (SU) KAYNAĞI (PARAMETRİK) =========================
waste = struct();                                                                  % Atık ısı akışı (su)
waste.Tin_C     = 122.4;                                                           % Kaska 2014 Case-1 giriş sıcaklığı [°C]
waste.mdot_kg_s = 16.23;                                                           % Kaska 2014 Case-1 debi [kg/s]
waste.P_bar     = 1.0;                                                             % Su basıncı varsayımı [bar] (PropsSI için)
waste.fluid     = 'Water';                                                         % CoolProp su adı

% Atık su hedef evaporatör giriş sıcaklığı (State-1) – sen burayı parametrik tarayacaksın
hx = struct();                                                                     % PTC->Atık su eşanjör ayarları
hx.Tout_waste_target_C = 123.0;                                                    % Örnek hedef [°C] (parametrik yap)
hx.model              = 'epsilon_NTU_counterflow';                                 % Model tipi (şimdilik)
hx.allow_UA_solve     = true;                                                      % UA_required çöz
hx.UA_WK              = NaN;                                                       % Eğer UA biliniyorsa buraya yazılabilir

%% ========================= 2b) HIZLANDIRMA: Water cp(T) LUT (1 kez) =========================
% Amaç: pinch çözümünde binlerce PropsSI('C',...) çağrısı yerine interp kullanmak.
% Fiziksel model değişmez: cp(T,P) yine CoolProp'tan alınır, sadece önceden örneklenip interpolasyon yapılır.

cfg.cpLUT = struct();                                                              % LUT yapısı
cfg.cpLUT.enabled = false;                                                         % Varsayılan kapalı (aşağıda açılabilir)
cfg.cpLUT.fluid   = waste.fluid;                                                   % LUT akışkanı (Water)
cfg.cpLUT.P_Pa    = waste.P_bar * 1e5;                                              % LUT basıncı [Pa]

if cfg.use_cpLUT                                                                      % LUT isteniyorsa
    cfg.cpLUT.enabled = true;                                                      % LUT’yi aktif et
    TminLUT = 273.15;                                                              % LUT alt sıcaklık [K]
    TmaxLUT = 520.00;                                                              % LUT üst sıcaklık [K] (160°C=433K üstü için pay bırak)
    NT_LUT  = 150;                                                                 % LUT nokta sayısı (400-600 iyi)
    cfg.cpLUT.T  = linspace(TminLUT, TmaxLUT, NT_LUT);                             % LUT sıcaklık ızgarası
    cfg.cpLUT.cp = zeros(size(cfg.cpLUT.T));                                       % LUT cp dizisi

    for i=1:numel(cfg.cpLUT.T)                                                     % LUT doldurma döngüsü
        cfg.cpLUT.cp(i) = PropsSI('C','T',cfg.cpLUT.T(i),'P',cfg.cpLUT.P_Pa,cfg.cpLUT.fluid); % cp(T,P)
    end
end

%% ========================= 3) PTC TEK MODÜL PARAMETRELERİ =========================
sigma = 5.670374e-8;                                                               % Stefan–Boltzmann [W/m^2-K^4]

ptc = struct();                                                                    % PTC geometri/optik
ptc.W   = 5.0;                                                                     % Kolektör genişliği [m]
ptc.L   = 7.8;                                                                     % Kolektör uzunluğu [m]
ptc.Aa  = 39.0;                                                                    % Aperture alanı [m^2]
ptc.Dri = 66e-3;                                                                   % Absorber iç çap [m]
ptc.Dro = 70e-3;                                                                   % Absorber dış çap [m]
ptc.Dci = 109e-3;                                                                  % Cam iç çap [m]
ptc.Dco = 115e-3;                                                                  % Cam dış çap [m]
ptc.eps_c = 0.86;                                                                  % Cam emisyon [-]

ptc.r_mirror   = 0.83;                                                             % Ayna yansıtıcılığı [-]
ptc.tau_cover  = 0.95;                                                             % Cam geçirgenliği [-]
ptc.alpha_abs  = 0.96;                                                             % Absorber soğurma [-]
ptc.gamma_int  = 1.00;                                                             % Intercept [-]
ptc.theta_deg  = 0.0;                                                              % Geliş açısı [deg]
ptc.K_theta    = 1.0;                                                              % IAM [-]
ptc.eta_opt    = ptc.r_mirror * ptc.tau_cover * ptc.alpha_abs * ptc.gamma_int * ptc.K_theta; % Optik verim [-]

ptc.Ari = pi*ptc.Dri*ptc.L;                                                        % Absorber iç alan [m^2]
ptc.Aro = pi*ptc.Dro*ptc.L;                                                        % Absorber dış alan [m^2]
ptc.Aci = pi*ptc.Dci*ptc.L;                                                        % Cam iç alan [m^2]
ptc.Aco = pi*ptc.Dco*ptc.L;                                                        % Cam dış alan [m^2]

R = 1.0;                                                                           % Nu çarpanı (R=1: düz boru)

%% ========================= 4) PTC SAHA (SERİ/PARALEL) + GİRİŞLER =========================
field = struct();                                                                  % Saha konfigürasyonu
field.N_series   = 12;                                                             % Seri modül sayısı (parametrik)
field.N_parallel = 12;                                                             % Paralel string sayısı (parametrik)

inPTC = struct();                                                                  % PTC çevresel girişler
inPTC.Gb_Wm2    = 509;                                                             % DNI [W/m^2]
inPTC.Vwind_ms  = 2.2;                                                             % Rüzgar [m/s]
inPTC.Tam_K     = 295;                                                             % Ortam [K]
inPTC.Tin_K     = 380.0;                                                           % PTC saha giriş (string giriş) [K]
inPTC.V_Lmin_1module = 56.8;                                                       % 1 modül için verilen debi [L/min] (senin tanımın)

%% ========================= 5) ORC PARAMETRELERİ =========================
orc = struct();                                                                     % ORC parametreleri
orc.fluid      = 'R245fa';                                                          % ORC akışkanı
orc.P_evap_bar = 10.8;                                                              % Evaporatör basıncı [bar]
orc.P_cond_bar = 2.1;                                                               % Kondenser basıncı [bar]
orc.eta_turb   = 0.78;                                                              % Türbin izentropik verimi [-]
orc.eta_pump   = 0.70;                                                              % Pompa izentropik verimi [-]

%% ========================= 6) KONDENSER (AIR-COOLED) PARAMETRELERİ =========================
cond = struct();                                                                   % Kondenser parametreleri
cond.Tair_in_C     = 25.0;                                                         % Dış hava giriş sıcaklığı [°C] (parametrik)
cond.Pamb_Pa       = 101325;                                                       % Atmosfer basıncı [Pa]
cond.mdot_air_kg_s = 300.0;                                                        % Hava debisi [kg/s] (parametrik)
cond.cp_air_JkgK   = 1007;                                                         % Hava cp ~ sabit [J/kg-K]
cond.eta_fan       = 0.60;                                                         % Fan toplam verimi [-]

cond.dp_model      = 'K_dp';                                                       % 'K_dp' veya 'yumrutas_bank'
cond.K_dp          = 3.0;                                                          % Δp = K*(0.5*rho*V^2) için K (örnek)
cond.V_face_ms     = 3.0;                                                          % Yüzey hızı [m/s] (örnek)
cond.rho_air_kg_m3 = NaN;                                                          % Hesaplanacak (Tair, Pamb)

cond.bank.sigma    = 0.2;                                                          % (örnek) büzülme/kontraksiyon parametresi
cond.bank.f        = 0.08;                                                         % (örnek) sürtünme faktörü
cond.bank.A        = 1.0;                                                          % (örnek) toplam alan oranı terimi
cond.bank.A_ff     = 1.0;                                                          % (örnek) serbest akış alanı
cond.bank.G_kg_m2s = 3.0;                                                          % (örnek) kütlesel hız G
cond.bank.v_in     = NaN;                                                          % özgül hacim (1/rho) [m3/kg]
cond.bank.v_out    = NaN;                                                          % çıkış özgül hacim [m3/kg]
cond.bank.v_m      = NaN;                                                          % ortalama özgül hacim [m3/kg]

%% ========================= 7) ÇÖZÜM AKIŞI =========================

% ---- 7.1) PTC SAHA ÇÖZ (SERİ/PARALEL) ----
ptc_field = ptc_solve_field_series_parallel(inPTC, ptc, field, R, sigma, opts);    % Saha çözümü

if cfg.show_tables
    disp("=== PTC FIELD Results ===");                                             % Başlık
    disp(ptc_field.table);                                                        % Saha tablosu
end

%% ==
% ---- 7.2) PTC -> ATIK SU EŞANJÖRÜ (UA required) ----
tPTCs = tic;                                                                      % (HIZ) pinch solve süre ölçümü başlat

if cfg.use_HX_preheat
    hx_out = hx_counterflow_UA_required( ...
        ptc_field.Th_out_K, ptc_field.mdot_hot_kg_s, 'syltherm800', ...                % Hot side (PTC oil)
        waste.Tin_C + 273.15, waste.mdot_kg_s, waste.fluid, waste.P_bar, ...           % Cold side (waste water)
        hx.Tout_waste_target_C + 273.15, cfg.deltaTmin_HX_K);                          % Target + ΔTmin

else
    % --- BYPASS: HX yok, preheat yok ---
    hx_out = struct();
    hx_out.Tcold_in_K  = waste.Tin_C + 273.15;
    hx_out.Tcold_out_K = waste.Tin_C + 273.15;
    hx_out.Th_in_K     = NaN;
    hx_out.Th_out_K    = NaN;
    hx_out.Q_W         = 0;
    hx_out.UA_WK       = 0;
    hx_out.DTmin_K     = NaN;
    hx_out.msg         = 'HX bypass (no preheat).';
end

% Evaporator hot inlet:
evap_hot.Tin_K = hx_out.Tcold_out_K;  % bypass modunda zaten Tin olur
evap_hot.mdot_kg_s = waste.mdot_kg_s;
evap_hot.P_bar = waste.P_bar;


fprintf("PTCs solve time: %.2f s\n", toc(tPTCs));                                % (HIZ) pinch süresini yazdır

if cfg.show_tables
    disp("=== PTC -> Waste Water HX (UA solve) ===");                              % Başlık

    % --- HX sonuçlarını "tek satırlık tablo" formatında yazdır (struct/table uyumlu)
    if istable(hx_out)                                                             % HX zaten table ise
        HX_disp = hx_out;                                                          % Kopya al (orijinali bozma)
    else
        HX_disp = struct2table(hx_out, "AsArray", true);                           % 1 satırlık table'a çevir
    end

    % --- SADECE GÖSTERİM: K -> °C dönüşümü
    HX_disp.Th_in_C     = HX_disp.Th_in_K    - 273.15;                             % Hot in [°C]
    HX_disp.Th_out_C    = HX_disp.Th_out_K   - 273.15;                             % Hot out [°C]
    HX_disp.Tcold_in_C  = HX_disp.Tcold_in_K - 273.15;                             % Cold in [°C]
    HX_disp.Tcold_out_C = HX_disp.Tcold_out_K- 273.15;                             % Cold out [°C]

    % --- K sütunlarını kaldır
    HX_disp = removevars(HX_disp, {'Th_in_K','Th_out_K','Tcold_in_K','Tcold_out_K'}); % Kelvin kolonlarını kaldır

    % --- °C sütunlarını msg'den sonra sırala (görünüm)
    HX_disp = movevars(HX_disp, {'Th_in_C','Th_out_C','Tcold_in_C','Tcold_out_C'}, "After", "msg"); % Yer değiştir

    disp(HX_disp);                                                                 % Tek satırlık tablo çıktısı
end

%% ==
% ---- 7.3) ATIK SU (STATE-1) -> ORC EVAPORATÖRÜ (PINCH KORUNUR) ----
evap_hot = struct();                                                               % Evap hot taraf
evap_hot.fluid      = 'Water';                                                     % Su
evap_hot.P_bar      = waste.P_bar;                                                 % Basınç varsayımı
evap_hot.mdot_kg_s  = waste.mdot_kg_s;                                             % Debi sabit
evap_hot.Tin_K      = hx_out.Tcold_out_K;                                          % State-1: evaporatör hot inlet [K]

tPinch = tic;                                                                      % (HIZ) pinch solve süre ölçümü başlat
out = coupled_hot_orc_pinch_solve(evap_hot, orc, cfg);                             % Pinch ile akuple çöz
fprintf("Pinch solve time: %.2f s\n", toc(tPinch));                                % (HIZ) pinch süresini yazdır

if cfg.show_tables
    disp("=== Coupled WasteWater(1)->ORC Evaporator (Pinch) Results ===");         % Başlık
    disp(struct2table(flatten_out_for_table(out, evap_hot, orc, cfg)));            % cfg eklendi (deltaT_pinch NaN olmaz)
end

%% ==
% ---- 7.4) KONDENSER: Qcon’u atacak UA_required + FAN GÜCÜ ----

tKondes = tic;                                                                      % (HIZ) pinch solve süre ölçümü başlat
cond_out = condenser_aircooled_UA_and_fan(orc, out, cond);                         % Kondenser çöz
fprintf("COndenser solve time: %.2f s\n", toc(tKondes));                                % (HIZ) pinch süresini yazdır

if cfg.show_tables
    disp("=== Air-cooled Condenser (UA required + Fan) ===");                      % Başlık
    disp(struct2table(cond_out));                                                  % Özet
end


%% ========================= 8) PLOTS =========================


if cfg.make_plots
    plot_hx_Tx_counterflow(hx_out);                                                % HX T-x profili
end


if cfg.make_plots
    if out.ok
        plot_evaporator_Tx_counterflow_generic(evap_hot, out, cfg);                % Evaporatör T-x
        %plot_orc_ts_diagram(out, orc);                                             % ORC T-s
    else
        figure; axis off; title('Evaporator pinch solve failed');                  % Uyarı
        text(0.05,0.5, out.msg, 'Interpreter','none');                             % Mesaj
    end
end


if cfg.make_plots
    plot_condenser_TQ(out, cond_out, cond);                                        % Kondenser T-Q görseli
end


tElapsed = toc(tStart);                                                            % Geçen süre [s]
fprintf("\n=== TOTAL RUNTIME ===\n");                                               % Başlık
fprintf("Total solve time: %.3f s (%.2f min)\n", tElapsed, tElapsed/60);            % Süre yazdır

%% =========================================================================================
%% ============================== LOCAL FUNCTIONS ===========================================
%% =========================================================================================
function ptc_field = ptc_solve_field_series_parallel(inPTC, ptc, field, R, sigma, opts)
% PTC saha çözümü (seri/paralel) - (HIZ) fsolve başlangıç tahmini bir önceki modülden beslenir

ptc_field = struct();                                                              % Çıktı
Np = field.N_parallel;                                                             % Paralel sayısı
Ns = field.N_series;                                                               % Seri sayısı

V_Lmin_mod = inPTC.V_Lmin_1module;                                                 % 1 modül debisi [L/min]
V_m3s_mod  = V_Lmin_mod*1e-3/60; %#ok<NASGU>                                       % [m3/s] (bilgi amaçlı)
Tin_string_K = inPTC.Tin_K;                                                        % String giriş [K]

Tin_now_K = Tin_string_K;                                                          % Seri başlangıç Tin
Qu_string_W = 0;                                                                   % String toplam Qu
dP_string_Pa = 0;                                                                  % String toplam dP
Tout_last_K = Tin_now_K;                                                           % Son çıkış

x0_prev = [];                                                                       % (HIZ) Önceki modülün çözümü: [Tr; Tc; Tout]

for k = 1:Ns                                                                       % Seri modüller döngüsü
    in = struct();                                                                 % Tek modül girişleri
    in.Gb     = inPTC.Gb_Wm2;                                                      % DNI
    in.Vwind  = inPTC.Vwind_ms;                                                    % Rüzgar
    in.Tam    = inPTC.Tam_K;                                                       % Ortam
    in.Tin    = Tin_now_K;                                                         % Modül Tin
    in.V_Lmin = V_Lmin_mod;                                                        % Modül debisi

    % (HIZ) fsolve başlangıç tahmini: bir önceki modülün çözümünü kullan
    if isempty(x0_prev)
        x0_use = [];                                                               % İlk modülde varsayılan x0 kullanılsın
    else
        x0_use = x0_prev;                                                          % Önceki çözümü taşı

        % (STABİL) Basit fiziksel sınırlar/iyileştirmeler
        x0_use(1) = max(x0_use(1), in.Tin);                                         % Tr >= Tin
        x0_use(3) = max(x0_use(3), in.Tin + 0.5);                                   % Tout >= Tin + küçük marj
        x0_use(2) = min(max(x0_use(2), in.Tam), x0_use(1));                         % Tc: Tam..Tr aralığına sıkıştır
    end

    out1 = ptc_solve_singleModule(in, ptc, R, sigma, opts, x0_use);                 % Tek modül çöz (x0 beslemeli)

    Tin_now_K    = out1.Tout_K;                                                    % Sonraki modül Tin
    Tout_last_K  = out1.Tout_K;                                                    % String çıkışı
    Qu_string_W  = Qu_string_W  + out1.Qu_W;                                       % Qu topla
    dP_string_Pa = dP_string_Pa + out1.dP_abs_Pa;                                  % dP topla

    % (HIZ) Sonraki modül için başlangıç tahminini güncelle
    x0_prev = [out1.Tr_K; out1.Tc_K; out1.Tout_K];
end

Qu_total_W   = Np * Qu_string_W;                                                   % Toplam Qu [W]
mdot_hot_str = out1.mdot_kg_s;                                                     % Tek string mdot
mdot_hot_tot = Np * mdot_hot_str;                                                  % Toplam mdot
dP_total_Pa  = dP_string_Pa;                                                       % Paralelde pompa dP değişmez

ptc_field.Th_in_K  = Tin_string_K;                                                 % Hot-in [K]
ptc_field.Th_out_K = Tout_last_K;                                                  % Hot-out [K]
ptc_field.mdot_hot_kg_s = mdot_hot_tot;                                            % Toplam hot mdot
ptc_field.Qu_total_W = Qu_total_W;                                                 % Toplam Qu
ptc_field.dP_hot_Pa = dP_total_Pa;                                                 % dP
ptc_field.Ns = Ns;                                                                 % Ns
ptc_field.Np = Np;                                                                 % Np

ptc_field.table = table( ...
    Ns, Np, inPTC.Gb_Wm2, inPTC.Tin_K, Tout_last_K, mdot_hot_tot, Qu_total_W, dP_total_Pa, ...
    'VariableNames', {'N_series','N_parallel','Gb_Wm2','Tin_field_K','Tout_field_K','mdot_hot_kg_s','Qu_total_W','dP_hot_Pa'} );
end

function out = ptc_solve_singleModule(in, ptc, R, sigma, opts, x0_in)
% Tek PTC modül çözümü (HIZ) - x0_in verilirse fsolve buna yakın başlar
% x0_in: [Tr; Tc; Tout] (K)

% Başlangıç [Tr,Tc,Tout]
if nargin < 6 || isempty(x0_in)
    x0 = [in.Tin+40; in.Tam+20; in.Tin+20];                                        % Varsayılan başlangıç
else
    x0 = x0_in(:);                                                                 % Dışarıdan gelen tahmin

    % (STABİL) Basit fiziksel sınırlar (fsolve'un saçma yerlere gitmesini azaltır)
    x0(1) = max(x0(1), in.Tin);                                                    % Tr >= Tin
    x0(3) = max(x0(3), in.Tin + 0.5);                                              % Tout >= Tin + küçük marj
    x0(2) = min(max(x0(2), in.Tam), x0(1));                                        % Tc: Tam..Tr
end

% Residual
f  = @(x) residuals_ptc(x, in.Gb, in.Vwind, in.Tam, in.Tin, in.V_Lmin, R, ptc, sigma);

% Çöz
[x, ~, exitflag] = fsolve(f, x0, opts);

% (STABİL) Nadiren fsolve başarısız olursa, bir kez de varsayılan x0 ile dene
if exitflag <= 0
    x0_fb = [in.Tin+40; in.Tam+20; in.Tin+20];
    x  = fsolve(f, x0_fb, opts);
end

Tr   = x(1);                                                                       % Tr [K]
Tc   = x(2);                                                                       % Tc [K]
Tout = x(3);                                                                       % Tout [K]

Tfm = 0.5*(in.Tin+Tout);                                                           % Ortalama T [K]
[rho, cp, k, mu] = syltherm800_props(Tfm);                                         % Özellikler

V_m3s  = in.V_Lmin*1e-3/60;                                                        % Debi [m3/s]
mdot   = rho*V_m3s;                                                                % mdot [kg/s]

Re = 4*mdot/(pi*ptc.Dri*mu);                                                       % Re
Pr = mu*cp/k;                                                                      % Pr
Nu0 = 0.023*(Re^0.8)*(Pr^0.4);                                                     % Dittus–Boelter
Nu  = R*Nu0;                                                                       % Nu
h   = Nu*k/ptc.Dri;                                                                % h_i

Qs   = ptc.Aa*in.Gb;                                                               % Işınım [W]
Qabs = Qs*ptc.eta_opt;                                                             % Soğurulan [W]
Qu   = mdot*cp*(Tout-in.Tin);                                                      % Qu [W]

Aflow = pi*(ptc.Dri^2)/4;                                                          % Akış alanı
u     = mdot/(rho*Aflow);                                                          % Hız
fr    = 1/( (0.79*log(Re) - 1.64)^2 );                                             % Darcy f
dP    = fr*(ptc.L/ptc.Dri)*(0.5*rho*u^2);                                          % dP [Pa]

out = struct();                                                                    % Çıktı
out.Tout_K     = Tout;                                                             % Tout
out.Tr_K       = Tr;                                                               % Tr
out.Tc_K       = Tc;                                                               % Tc
out.mdot_kg_s  = mdot;                                                             % mdot
out.Qu_W       = Qu;                                                               % Qu
out.Qabs_W     = Qabs;                                                             % Qabs
out.Re         = Re;                                                               % Re
out.dP_abs_Pa  = dP;                                                               % dP
out.h_i_Wm2K   = h;                                                                % h
end


function hx_out = hx_counterflow_UA_required(Th_in_K, mdot_h, hotType, Tc_in_K, mdot_c, coldFluid, coldP_bar, Tc_out_target_K, deltaTmin_K)
% Counterflow ε–NTU ile UA_required hesapla (hedef Tc_out için).
hx_out = struct();                                                                 % Çıktı
hx_out.ok = false;                                                                 % Başlangıç
hx_out.msg = '';                                                                   % Mesaj

Th_guess_out_K = Th_in_K - 10;                                                     % Basit tahmin
Th_mean_K = 0.5*(Th_in_K + Th_guess_out_K);                                        % Hot mean

cp_h = get_cp_hot(hotType, Th_mean_K, coldP_bar);                                  % Hot cp
cp_c = get_cp_cold(coldFluid, coldP_bar, 0.5*(Tc_in_K + Tc_out_target_K));         % Cold cp

C_h = mdot_h * cp_h;                                                               % C_h
C_c = mdot_c * cp_c;                                                               % C_c

Cmin = min(C_h, C_c);                                                              % Cmin
Cmax = max(C_h, C_c);                                                              % Cmax
Cr   = Cmin / Cmax;                                                                % Cr

Q_req_W = mdot_c * cp_c * (Tc_out_target_K - Tc_in_K);                             % Q_req
Qmax_W  = Cmin * (Th_in_K - Tc_in_K);                                              % Qmax

if Q_req_W <= 0                                                                    % hedef kontrol
    hx_out.msg = 'Invalid target: Tc_out_target <= Tc_in.';                        % mesaj
    return
end
if Q_req_W >= Qmax_W                                                               % fiziksellik
    hx_out.msg = sprintf('HX infeasible: Q_req=%.2f kW >= Qmax=%.2f kW.', Q_req_W/1000, Qmax_W/1000); % mesaj
    return
end

Th_out_K = Th_in_K - Q_req_W / C_h;                                                % enerji ile Th_out

DT1 = Th_in_K  - Tc_out_target_K;                                                  % uç 1 yaklaşma
DT2 = Th_out_K - Tc_in_K;                                                          % uç 2 yaklaşma
DTmin_actual = min(DT1, DT2);                                                      % min yaklaşma

if DTmin_actual < deltaTmin_K                                                      % ΔTmin kontrolü
    hx_out.msg = sprintf('ΔTmin violated: min(ΔT)=%.2f K < %.2f K.', DTmin_actual, deltaTmin_K); % mesaj
    return
end

epsilon = Q_req_W / Qmax_W;                                                        % ε

if abs(Cr - 1) < 1e-6                                                              % Cr~1 durumu
    NTU = epsilon/(1-epsilon);                                                     % ε=NTU/(1+NTU)
else
    fun = @(NTU) ( (1 - exp(-NTU*(1-Cr))) / (1 - Cr*exp(-NTU*(1-Cr))) ) - epsilon; % counterflow bağıntı
    NTU = fzero(fun, [1e-6, 200]);                                                 % NTU çöz
end

UA_WK = NTU * Cmin;                                                                % UA

hx_out.ok = true;                                                                  % OK
hx_out.msg = 'OK';                                                                 % mesaj

hx_out.Th_in_K     = Th_in_K;                                                      % Hot in
hx_out.Th_out_K    = Th_out_K;                                                     % Hot out
hx_out.Tcold_in_K  = Tc_in_K;                                                      % Cold in
hx_out.Tcold_out_K = Tc_out_target_K;                                              % Cold out

hx_out.cp_hot_JkgK  = cp_h;                                                        % cp hot
hx_out.cp_cold_JkgK = cp_c;                                                        % cp cold

hx_out.C_hot_WK  = C_h;                                                            % C hot
hx_out.C_cold_WK = C_c;                                                            % C cold
hx_out.Cr        = Cr;                                                             % Cr

hx_out.Q_req_kW  = Q_req_W/1000;                                                   % Q
hx_out.Qmax_kW   = Qmax_W/1000;                                                    % Qmax
hx_out.epsilon   = epsilon;                                                        % eps
hx_out.NTU       = NTU;                                                            % NTU
hx_out.UA_WK     = UA_WK;                                                          % UA

hx_out.DT_end1_K = DT1;                                                            % uç 1
hx_out.DT_end2_K = DT2;                                                            % uç 2
hx_out.DTmin_K   = DTmin_actual;                                                   % min
end



function out = coupled_hot_orc_pinch_solve(hot, orc, cfg)
% coupled_hot_orc_pinch_solve
% ORC evaporatör pinch coupling (Kaska 2014 Fig.3 mantığı)
%
% GİRİŞ:
%   hot.Tin_K        : Hot-stream evaporatör giriş sıcaklığı [K]
%   hot.mdot_kg_s    : Hot-stream kütlesel debi [kg/s]
%   hot.fluid        : Hot-stream akışkan adı (örn. 'Water' veya 'syltherm800')
%   hot.P_bar        : Hot-stream basıncı [bar] (CoolProp için)
%
%   orc.fluid        : ORC akışkanı (örn. 'R245fa')
%   orc.P_evap_bar   : Evaporatör basıncı [bar]
%   orc.P_cond_bar   : Kondenser basıncı [bar]
%   orc.eta_turb     : Türbin izentropik verimi [-]
%   orc.eta_pump     : Pompa izentropik verimi [-]
%
%   cfg.deltaT_pinch_K : Pinch yaklaşımı [K] (Thot_pp = Tevap + ΔTpinch)
%   cfg.orc_design_mode:
%       'pinch_only'   : (ESKİ) mdot_r = Q(Tin->Tpp) / (h3-hf)
%       'kaska_totalQ' : (YENİ) mdot_r = Q(Tin->Tout) / (h3-h6) ve pinch kısıt kontrol
%
%   cfg.max_iter_orc  : (opsiyonel) iter limiti (vars: 60)
%   cfg.tol_Tout_K    : (opsiyonel) Tout toleransı (vars: 1e-4 K)
%   cfg.tol_mdot_rel  : (opsiyonel) mdot bağıl tolerans (vars: 1e-6)
%
% ÇIKIŞ:
%   out.ok, out.msg
%   out.Thot_pp_K, out.Thot_out_K
%   out.Qevap_hot_kW (Tin->Tpp)
%   out.Qpre_req_kW  (ORC: 6->f)
%   out.Qev_available_kW (Tin->Tout toplam hot-side ısı)
%   out.mdot_r
%   out.Wt_kW, out.Wp_kW, out.Wnet_kW
%   out.Qev_kW, out.Qcon_kW, out.eta_th
%   out.energy_closure_kW

    out = struct();                                                                % Çıktı struct'ı
    out.ok  = false;                                                               % Başlangıç: başarısız
    out.msg = '';                                                                  % Mesaj

    out.states            = struct([]);                                            % ORC state dizisi
    out.Thot_pp_K         = NaN;                                                   % Pinch hot sıcaklığı [K]
    out.Thot_out_K        = NaN;                                                   % Hot çıkış [K]
    out.Qevap_hot_kW      = NaN;                                                   % Hot: Tin->Tpp ısı [kW]
    out.Qpre_req_kW       = NaN;                                                   % ORC preheat ihtiyacı [kW]
    out.Qev_available_kW  = NaN;                                                   % Hot: Tin->Tout toplam ısı [kW]
    out.mdot_r            = NaN;                                                   % ORC debisi [kg/s]
    out.Wt_kW             = NaN;                                                   % Türbin gücü [kW]
    out.Wp_kW             = NaN;                                                   % Pompa gücü [kW]
    out.Wnet_kW           = NaN;                                                   % Net güç [kW]
    out.Qev_kW            = NaN;                                                   % Evaporatör ısısı [kW]
    out.Qcon_kW           = NaN;                                                   % Kondenser ısısı [kW]
    out.eta_th            = NaN;                                                   % Termal verim [-]
    out.energy_closure_kW = NaN;                                                   % Enerji kapanışı [kW]

    try
        % -----------------------------
        % 0) cfg varsayılanları
        % -----------------------------
        if ~isfield(cfg,'orc_design_mode') || isempty(cfg.orc_design_mode)
            cfg.orc_design_mode = 'pinch_only';                                    % Varsayılan mod
        end
        if ~isfield(cfg,'max_iter_orc') || isempty(cfg.max_iter_orc)
            cfg.max_iter_orc = 60;                                                 % iter limit
        end
        if ~isfield(cfg,'tol_Tout_K') || isempty(cfg.tol_Tout_K)
            cfg.tol_Tout_K = 1e-4;                                                 % Tout toleransı
        end
        if ~isfield(cfg,'tol_mdot_rel') || isempty(cfg.tol_mdot_rel)
            cfg.tol_mdot_rel = 1e-6;                                               % mdot bağıl tolerans
        end

        % -----------------------------
        % 1) Hot-side girişler
        % -----------------------------
        Thot_in_K = hot.Tin_K;                                                     % Hot giriş [K]
        mdot_hot  = hot.mdot_kg_s;                                                 % Hot debi [kg/s]

        % -----------------------------
        % 2) ORC çevrimini çöz
        % -----------------------------
        sp = orc_specific_cycle(orc);                                              % ORC state ve entalpiler
        out.states = sp.states;                                                    % state'leri kaydet

        fluid = orc.fluid;                                                         % ORC akışkanı
        Pevap = orc.P_evap_bar * 1e5;                                              % Evap basıncı [Pa]

        Tevap_K = sp.states(3).T_C + 273.15;                                       % Tevap [K] (sat buhar @ Pevap)
        h3      = sp.h3;                                                           % [J/kg] state-3
        h6      = sp.h6;                                                           % [J/kg] state-6
        hf      = PropsSI('H','P',Pevap,'Q',0,fluid);                              % [J/kg] sat sıvı h @ Pevap

        % -----------------------------
        % 3) Pinch sıcaklığı (hot)
        % -----------------------------
        Thot_pp_K = Tevap_K + cfg.deltaT_pinch_K;                                  % Pinch hot sıcaklığı [K]
        out.Thot_pp_K = Thot_pp_K;                                                 % kaydet

        % Fiziksellik kontrolleri
        if Thot_in_K <= Thot_pp_K
            error('Pinch infeasible: Thot_in (%.2f K) <= Thot_pp (%.2f K).', Thot_in_K, Thot_pp_K);
        end
        if hf <= h6
            error('ORC preheat invalid: hf <= h6. Check ORC cycle calculation.');
        end

        % -----------------------------
        % 4) Tin -> Tpp arası hot-side ısı (evap bölgesi)
        % -----------------------------
        Q_to_pinch_W = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_pp_K, hot.fluid, hot.P_bar, cfg); % [W]
        out.Qevap_hot_kW = Q_to_pinch_W/1000;                                      % [kW]

        % =====================================================================
        % 5) MOD-1: pinch_only (ESKİ) -> mdot sadece Tin->Tpp ısısından
        % =====================================================================
        if strcmpi(cfg.orc_design_mode,'pinch_only')

            mdot_r = Q_to_pinch_W / max((h3 - hf), 1e-12);                          % mdot_r [kg/s]
            out.mdot_r = mdot_r;                                                   % kaydet

            Qpre_req_W = mdot_r * (hf - h6);                                       % ORC preheat ihtiyacı [W]
            out.Qpre_req_kW = Qpre_req_W/1000;                                     % [kW]

            % Tout: hot(pp->out) sağladığı ısı = Qpre_req
            f = @(Tout) hot_Qdot_integral(mdot_hot, Thot_pp_K, Tout, hot.fluid, hot.P_bar, cfg) - Qpre_req_W;

            Tout_high = Thot_pp_K - 1e-6;                                          % üst sınır (pinch altı)
            Tout_low  = 273.15;                                                    % alt sınır (güvenli)

            fa = f(Tout_low);                                                      % alt uç
            fb = f(Tout_high);                                                     % üst uç

            if ~isfinite(fa) || ~isfinite(fb) || sign(fa)==sign(fb)
                error(['Preheat bracket not found (pinch_only). ' ...
                       'Try lowering deltaT_pinch or check hot capacity.']);
            end

            Thot_out_K = fzero(f, [Tout_low, Tout_high]);                          % Tout çöz [K]
            out.Thot_out_K = Thot_out_K;                                           % kaydet

            Qtotal_W = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_out_K, hot.fluid, hot.P_bar, cfg); % [W]
            out.Qev_available_kW = Qtotal_W/1000;                                  % [kW]

        % =====================================================================
        % 6) MOD-2: kaska_totalQ (YENİ) -> mdot toplam ısıdan, pinch kısıt kontrol
        % =====================================================================
        elseif strcmpi(cfg.orc_design_mode,'kaska_totalQ')

            % Başlangıç tahmini: eski formül, yakın bir başlangıç verir
            mdot_r = Q_to_pinch_W / max((h3 - hf), 1e-12);                          % mdot başlangıç [kg/s]
            Thot_out_K = NaN;                                                      % ilk iterasyonda yok

            for it = 1:cfg.max_iter_orc

                % (A) Bu mdot için ORC preheat ihtiyacı
                Qpre_req_W = mdot_r * (hf - h6);                                   % [W]

                % (B) Tout çöz: hot(pp->out) = Qpre_req
                f = @(Tout) hot_Qdot_integral(mdot_hot, Thot_pp_K, Tout, hot.fluid, hot.P_bar, cfg) - Qpre_req_W;

                Tout_high = Thot_pp_K - 1e-6;                                      % pinch altı
                Tout_low  = 273.15;                                                % alt sınır

                fa = f(Tout_low);
                fb = f(Tout_high);

                if ~isfinite(fa) || ~isfinite(fb) || sign(fa)==sign(fb)
                    error(['Preheat bracket not found (kaska_totalQ). ' ...
                           'Try lowering deltaT_pinch or check cycle/hot cp integral.']);
                end

                Thot_out_new_K = fzero(f, [Tout_low, Tout_high]);                  % yeni Tout [K]

                % (C) Toplam hot-side ısı: Tin->Tout
                Qtotal_hot_W = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_out_new_K, hot.fluid, hot.P_bar, cfg); % [W]

                % (D) mdot güncelle: Qtotal = mdot*(h3-h6)
                mdot_new = Qtotal_hot_W / max((h3 - h6), 1e-12);                   % [kg/s]

                % (E) Pinch kısıt kontrol: evaporasyon için gereken ısı Tin->Tpp ile karşılanmalı
                Qevap_req_W = mdot_new * (h3 - hf);                                % ORC evaporation ihtiyacı [W]
                if Qevap_req_W > Q_to_pinch_W*(1 + 1e-9)
                    error(['Pinch violated (kaska_totalQ): Qevap_req=%.2f kW > Q_to_pinch=%.2f kW. ' ...
                           'Reduce mdot_r (change cycle or pinch).'], Qevap_req_W/1000, Q_to_pinch_W/1000);
                end

                % (F) Yakınsama metrikleri
                if isfinite(Thot_out_K)
                    dTout = abs(Thot_out_new_K - Thot_out_K);                      % Tout değişimi [K]
                else
                    dTout = inf;                                                   % ilk iterasyon
                end
                dMrel = abs(mdot_new - mdot_r)/max(mdot_r, 1e-12);                 % mdot bağıl değişim

                % (G) Güncelle
                Thot_out_K = Thot_out_new_K;                                       % Tout güncelle
                mdot_r     = mdot_new;                                             % mdot güncelle

                % (H) Yakınsadıysa çık
                if dTout < cfg.tol_Tout_K && dMrel < cfg.tol_mdot_rel
                    break
                end
            end

            % Son değerleri kaydet
            out.Thot_out_K = Thot_out_K;                                           % Tout [K]
            out.mdot_r     = mdot_r;                                               % mdot [kg/s]

            % Isı bileşenlerini kaydet (son mdot ile)
            Qpre_req_W = mdot_r * (hf - h6);                                       % [W]
            out.Qpre_req_kW = Qpre_req_W/1000;                                     % [kW]

            Qtotal_hot_W = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_out_K, hot.fluid, hot.P_bar, cfg); % [W]
            out.Qev_available_kW = Qtotal_hot_W/1000;                              % [kW]

        else
            error('Unknown cfg.orc_design_mode = "%s".', string(cfg.orc_design_mode));
        end

        % -----------------------------
        % 7) Güç ve ısılar (ortak)
        % -----------------------------
        mdot_r = out.mdot_r;                                                       % kısaltma

        Wt_W   = mdot_r * (sp.h3 - sp.h4);                                         % türbin gücü [W]
        Wp_W   = mdot_r * (sp.h6 - sp.h5);                                         % pompa gücü [W]
        Wnet_W = Wt_W - Wp_W;                                                      % net güç [W]

        Qev_W  = mdot_r * (sp.h3 - sp.h6);                                         % evaporatör ısısı [W]
        Qcon_W = mdot_r * (sp.h4 - sp.h5);                                         % kondenser ısısı [W]
        eta_th = Wnet_W / max(Qev_W, 1e-12);                                       % verim [-]

        out.Wt_kW   = Wt_W/1000;                                                   % [kW]
        out.Wp_kW   = Wp_W/1000;                                                   % [kW]
        out.Wnet_kW = Wnet_W/1000;                                                 % [kW]
        out.Qev_kW  = Qev_W/1000;                                                  % [kW]
        out.Qcon_kW = Qcon_W/1000;                                                 % [kW]
        out.eta_th  = eta_th;                                                      % [-]

        out.energy_closure_kW = out.Qev_kW - out.Qcon_kW - out.Wnet_kW;             % [kW] (ideal ~0)

        % -----------------------------
        % 8) Başarılı
        % -----------------------------
        out.ok  = true;                                                            % başarılı
        out.msg = 'OK';                                                            % mesaj

    catch ME
        out.ok  = false;                                                           % başarısız
        out.msg = ME.message;                                                      % hata mesajı
    end
end




function flat = flatten_out_for_table(out, hot, orc, cfg)
% out struct’ını tabloya uygun sade özet haline getir
flat = struct();                                                                   % özet struct
flat.T_hot_in_C   = hot.Tin_K - 273.15;                                            % hot in [°C]
flat.mdot_hot     = hot.mdot_kg_s;                                                 % mdot hot
flat.Pevap_bar    = orc.P_evap_bar;                                                % Pevap
flat.Pcond_bar    = orc.P_cond_bar;                                                % Pcond
flat.deltaT_pinch = cfg.deltaT_pinch_K;                                            % (FIX) artık NaN değil
flat.Thot_pp_C    = out.Thot_pp_K - 273.15;                                        % pinch hot [°C]
flat.Thot_out_C   = out.Thot_out_K - 273.15;                                       % hot out [°C]
flat.Qevap_hot_kW = out.Qevap_hot_kW;                                              % evap bölgesi ısı
flat.Qpre_req_kW  = out.Qpre_req_kW;                                               % preheat ihtiyacı
flat.mdot_r       = out.mdot_r;                                                    % ORC mdot
flat.Wnet_kW      = out.Wnet_kW;                                                   % net güç
flat.eta_th       = out.eta_th;                                                    % verim
flat.Qcon_kW      = out.Qcon_kW;                                                   % kondenser yükü
flat.ok           = out.ok;                                                        % ok
flat.msg          = string(out.msg);                                               % msg
end

function Qdot_W = hot_Qdot_integral(mdot, Tin_K, Tout_K, hotFluid, P_bar, cfg)
% Genel integral: Qdot = mdot * ∫ cp(T) dT  (Tin > Tout ise pozitif çıkar)
% HIZ: Water için cp LUT varsa PropsSI yerine interp1 ile cp alır.

N = cfg.N_int;                                                                     % (HIZ) integral nokta sayısı
Tvec = linspace(Tout_K, Tin_K, N);                                                 % Tout -> Tin sıcaklık vektörü
cpvec = zeros(size(Tvec));                                                         % cp vektörü

for i = 1:numel(Tvec)                                                              % integral döngüsü
    if strcmpi(hotFluid, 'syltherm800')                                            % SYLTHERM ise
        [~, cp, ~, ~] = syltherm800_props(Tvec(i));                                % cp [J/kgK]
        cpvec(i) = cp;                                                             % cp ata
    else
        P_Pa = P_bar * 1e5;                                                        % Pa'ya çevir

        % (HIZ) LUT uygunsa cp'yi interpolasyonla al
        if isfield(cfg,'cpLUT') && isstruct(cfg.cpLUT) && isfield(cfg.cpLUT,'enabled') && cfg.cpLUT.enabled ...
                && strcmpi(hotFluid, cfg.cpLUT.fluid) && abs(P_Pa - cfg.cpLUT.P_Pa) < 1e-6
            cpvec(i) = interp1(cfg.cpLUT.T, cfg.cpLUT.cp, Tvec(i), 'linear', 'extrap'); % hızlı cp
        else
            cpvec(i) = PropsSI('C','T',Tvec(i),'P',P_Pa,hotFluid);                 % fallback (yavaş)
        end
    end
end

dH_Jkg = trapz(Tvec, cpvec);                                                       % ∫cp dT [J/kg]
Qdot_W = mdot * dH_Jkg;                                                            % Qdot [W]
end

function cp = get_cp_hot(hotType, T_K, P_bar)
if strcmpi(hotType, 'syltherm800')
    [~, cp, ~, ~] = syltherm800_props(T_K);
else
    P_Pa = P_bar*1e5;
    cp = PropsSI('C','T',T_K,'P',P_Pa,hotType);
end
end

function cp = get_cp_cold(fluid, P_bar, T_K)
P_Pa = P_bar*1e5;
cp = PropsSI('C','T',T_K,'P',P_Pa,fluid);
end



function plot_hx_Tx_counterflow(hx_out)
% HX T-x profili (basit lineer görselleştirme)
if ~hx_out.ok
    figure; axis off; title('HX solve failed');
    text(0.05,0.5, hx_out.msg, 'Interpreter','none');
    return
end

x = linspace(0,1,200);                                                             % Koordinat
Th = hx_out.Th_in_K  + (hx_out.Th_out_K  - hx_out.Th_in_K)*x;                      % Hot lineer
Tc = hx_out.Tcold_out_K + (hx_out.Tcold_in_K - hx_out.Tcold_out_K)*x;              % Cold counterflow (ters)

figure;
plot(x, Th-273.15,'LineWidth',1.8); hold on;
plot(x, Tc-273.15,'LineWidth',1.8);
xlabel('x (0: hot-in / cold-out, 1: hot-out / cold-in)');
ylabel('Temperature [°C]');
title(sprintf('PTC→Waste HX T-x (UA=%.1f kW/K, ΔTmin=%.1f K)', hx_out.UA_WK/1000, hx_out.DTmin_K));
grid on;
legend('Hot (PTC oil)','Cold (waste water)','Location','best');
end

function plot_evaporator_Tx_counterflow_generic(hot, out, cfg)
% ORC evaporatör T-x (Kaska Fig.3 stiline benzer)
% x=0 hot-in, x=1 hot-out
if ~out.ok
    figure; axis off; title('Evaporator solve failed');
    text(0.05,0.5, out.msg, 'Interpreter','none');
    return
end

Th_in  = hot.Tin_K;
Th_pp  = out.Thot_pp_K;
Th_out = out.Thot_out_K;

Tevap_K = out.states(3).T_C + 273.15;
T6_K    = out.states(6).T_C + 273.15;

% Isı fraksiyonundan pinch konumu (görsel)
Q_evap = out.Qevap_hot_kW*1000;
Q_pre  = out.Qpre_req_kW*1000;
Q_tot  = Q_evap + Q_pre;
x_pp   = Q_evap/max(Q_tot,1e-12);

x = linspace(0,1,400);
Th = zeros(size(x));
Tc = zeros(size(x));

for i=1:numel(x)
    if x(i) <= x_pp
        Th(i) = Th_in + (Th_pp - Th_in)*(x(i)/max(x_pp,1e-12));
        Tc(i) = Tevap_K;
    else
        Th(i) = Th_pp + (Th_out - Th_pp)*((x(i)-x_pp)/max(1-x_pp,1e-12));
        frac  = (x(i)-x_pp)/max(1-x_pp,1e-12);
        Tc(i) = Tevap_K + (T6_K - Tevap_K)*frac;
    end
end

figure;
plot(x, Th-273.15,'LineWidth',1.8); hold on;
plot(x, Tc-273.15,'LineWidth',1.8);
yline(Tevap_K-273.15,'--','LineWidth',1.0);
yline(Th_pp-273.15,'--','LineWidth',1.0);
plot(x_pp, Th_pp-273.15,'ko','LineWidth',1.4);
plot(x_pp, Tevap_K-273.15,'ko','LineWidth',1.4);

xlabel('Evaporator coordinate x (left=hot in, right=hot out)');
ylabel('Temperature [°C]');
title(sprintf('Waste-water→ORC Evaporator T-x (ΔTpinch=%.1f K)', cfg.deltaT_pinch_K));
grid on;
legend('Hot stream (waste water)','Cold stream (ORC)','T_{evap}','T_{pp}','Location','best');
end

function plot_condenser_TQ(out, cond_out, cond)
% Kondenser görsel (sıcak taraf ~ Tcond sabit, hava ısınır)
if ~cond_out.ok
    figure; axis off; title('Condenser solve failed');
    text(0.05,0.5, cond_out.msg, 'Interpreter','none');
    return
end

Q = linspace(0, cond_out.Qcon_kW, 200);                                            % [kW]
Tcond = cond_out.Tcond_sat_C * ones(size(Q));                                      % [°C] sabit

Tair_in_C = cond.Tair_in_C;
Tair_out_C = cond_out.Tair_out_C;
Tair = Tair_in_C + (Tair_out_C - Tair_in_C)*(Q/max(cond_out.Qcon_kW,1e-12));       % lineer

figure;
plot(Q, Tcond,'LineWidth',1.8); hold on;
plot(Q, Tair,'LineWidth',1.8);
xlabel('Cumulative heat rejected Q [kW]');
ylabel('Temperature [°C]');
title(sprintf('Air-cooled condenser T-Q (UA=%.1f kW/K, Wfan=%.2f kW)', cond_out.UA_WK/1000, cond_out.Wfan_kW));
grid on;
legend('Refrigerant (condensing at Tcond)','Air','Location','best');
end

%% ========================= ORC SPECIFIC CYCLE (SENİN KOD) =========================
function sp = orc_specific_cycle(orc)
% Verilen Pevap,Pcond,etaT,etaP ile state entalpilerini bulur.
% State-3: sat buhar @ Pevap
% State-5: sat sıvı  @ Pcond

sp = struct();

fluid = orc.fluid;
Pevap = orc.P_evap_bar * 1e5;
Pcond = orc.P_cond_bar * 1e5;
etaT  = orc.eta_turb;
etaP  = orc.eta_pump;

h3 = PropsSI('H','P',Pevap,'Q',1,fluid);
s3 = PropsSI('S','P',Pevap,'Q',1,fluid);
T3 = PropsSI('T','P',Pevap,'Q',1,fluid);
Q3 = PropsSI('Q','P',Pevap,'Q',1,fluid);

h4s = PropsSI('H','P',Pcond,'S',s3,fluid);
h4  = h3 - etaT*(h3 - h4s);
T4  = PropsSI('T','P',Pcond,'H',h4,fluid);
s4  = PropsSI('S','P',Pcond,'H',h4,fluid);
Q4  = PropsSI('Q','P',Pcond,'H',h4,fluid);

h5 = PropsSI('H','P',Pcond,'Q',0,fluid);
s5 = PropsSI('S','P',Pcond,'Q',0,fluid);
T5 = PropsSI('T','P',Pcond,'Q',0,fluid);
Q5 = PropsSI('Q','P',Pcond,'Q',0,fluid);

h6s = PropsSI('H','P',Pevap,'S',s5,fluid);
h6  = h5 + (h6s - h5)/etaP;
T6  = PropsSI('T','P',Pevap,'H',h6,fluid);
s6  = PropsSI('S','P',Pevap,'H',h6,fluid);
Q6  = PropsSI('Q','P',Pevap,'H',h6,fluid);

sp.h3 = h3; sp.h4 = h4; sp.h5 = h5; sp.h6 = h6;

sp.states = struct();

sp.states(3).P_bar   = orc.P_evap_bar;
sp.states(3).T_C     = T3 - 273.15;
sp.states(3).h_kJkg  = h3/1000;
sp.states(3).s_kJkgK = s3/1000;
sp.states(3).Q       = Q3;

sp.states(4).P_bar   = orc.P_cond_bar;
sp.states(4).T_C     = T4 - 273.15;
sp.states(4).h_kJkg  = h4/1000;
sp.states(4).s_kJkgK = s4/1000;
sp.states(4).Q       = Q4;

sp.states(5).P_bar   = orc.P_cond_bar;
sp.states(5).T_C     = T5 - 273.15;
sp.states(5).h_kJkg  = h5/1000;
sp.states(5).s_kJkgK = s5/1000;
sp.states(5).Q       = Q5;

sp.states(6).P_bar   = orc.P_evap_bar;
sp.states(6).T_C     = T6 - 273.15;
sp.states(6).h_kJkg  = h6/1000;
sp.states(6).s_kJkgK = s6/1000;
sp.states(6).Q       = Q6;
end

%% LOCAL FUNCTION: ORC T-s Diyagramı (FAST + SAFE vectorization)
%% =================================================================================================
function plot_orc_ts_diagram(out, orc)
% plot_orc_ts_diagram (FAST + SAFE)
%   Hız için PropsSI vektör çağrıları kullanılır.
%   SAFE katmanı ile PropsSI'nin NxN veya row/col sapmalarına karşı korumalıdır.

% =========================
% HIZ AYARLARI
% =========================
Nseg   = 40;                                                                        % Segment örnek sayısı (daha hızlı)
Ndome  = 120;                                                                       % Dome örnek sayısı (daha hızlı)
TloMin = 240;                                                                       % Dome alt sınır güvenli [K]

fluid = orc.fluid;                                                                  % Akışkan adı

% Basınçlar [Pa]
Pevap = orc.P_evap_bar * 1e5;                                                       % Evaporatör basıncı [Pa]
Pcond = orc.P_cond_bar * 1e5;                                                       % Kondenser basıncı [Pa]

% Nokta entalpileri [J/kg]
h3 = out.states(3).h_kJkg * 1000;                                                   % h3 [J/kg]
h4 = out.states(4).h_kJkg * 1000;                                                   % h4 [J/kg]
h5 = out.states(5).h_kJkg * 1000;                                                   % h5 [J/kg]
h6 = out.states(6).h_kJkg * 1000;                                                   % h6 [J/kg]

% Nokta sıcaklıkları [K]
T3 = out.states(3).T_C + 273.15;                                                    % T3 [K]
T4 = out.states(4).T_C + 273.15;                                                    % T4 [K]
T5 = out.states(5).T_C + 273.15;                                                    % T5 [K]
T6 = out.states(6).T_C + 273.15;                                                    % T6 [K]

% Nokta entropileri [J/kg-K]
s3 = out.states(3).s_kJkgK * 1000;                                                  % s3 [J/kg-K]
s4 = out.states(4).s_kJkgK * 1000;                                                  % s4 [J/kg-K]
s5 = out.states(5).s_kJkgK * 1000;                                                  % s5 [J/kg-K]
s6 = out.states(6).s_kJkgK * 1000;                                                  % s6 [J/kg-K]

% =========================
% SATURATION DOME (CACHED)
% =========================
persistent dome_fluid dome_Tv dome_sL dome_sV dome_maskL dome_maskV                 % Dome cache değişkenleri

if isempty(dome_fluid) || ~strcmp(dome_fluid, fluid)                                % İlk kez ya da fluid değiştiyse
    Tcrit = PropsSI('Tcrit', fluid);                                                % Kritik sıcaklık [K]
    Tmin  = PropsSI('Tmin',  fluid);                                                % Minimum sıcaklık [K]

    Tlo = max(Tmin + 5, TloMin);                                                    % Alt sınır [K]
    Thi = Tcrit - 1e-3;                                                             % Üst sınır [K]

    dome_Tv = linspace(Tlo, Thi, Ndome).';                                          % Dome sıcaklık vektörü (kolon) [K]

    dome_sL = PropsSI('S','T',dome_Tv,'Q',0,fluid);                                 % sat sıvı entropi (vektör beklenir)
    dome_sV = PropsSI('S','T',dome_Tv,'Q',1,fluid);                                 % sat buhar entropi (vektör beklenir)

    dome_sL = dome_sL(:);                                                           % NxN gelse bile tek vektöre indir
    dome_sV = dome_sV(:);                                                           % NxN gelse bile tek vektöre indir

    dome_maskL = isfinite(dome_sL) & isfinite(dome_Tv);                             % Sol dome maskesi
    dome_maskV = isfinite(dome_sV) & isfinite(dome_Tv);                             % Sağ dome maskesi

    idx = find(dome_maskL & dome_maskV, 1, 'last');                                 % Son geçerli nokta
    if ~isempty(idx)
        s_join         = 0.5*(dome_sL(idx) + dome_sV(idx));                         % Birleşim entropisi
        dome_sL(idx)   = s_join;                                                    % Sol ucu birleştir
        dome_sV(idx)   = s_join;                                                    % Sağ ucu birleştir
    end

    dome_fluid = fluid;                                                             % Cache: fluid adı
end

% =========================
% PROSES EĞRİLERİ (SAFE VECTOR)
% =========================

% --- 5 -> 6 (Pompa)
P_56 = linspace(Pcond, Pevap, Nseg).';                                              % P vektörü (kolon)
h_56 = linspace(h5,    h6,    Nseg).';                                              % h vektörü (kolon)
T_56 = PropsSI('T','P',P_56,'H',h_56,fluid);                                        % T(P,H)
s_56 = PropsSI('S','P',P_56,'H',h_56,fluid);                                        % s(P,H)
T_56 = T_56(:); s_56 = s_56(:);                                                     % NxN sapmasına karşı koruma

% --- 6 -> 3 (Evaporatör)
hf = PropsSI('H','P',Pevap,'Q',0,fluid);                                            % hf @ Pevap
hg = PropsSI('H','P',Pevap,'Q',1,fluid);                                            % hg @ Pevap

% 6 -> hf (preheat)
h_6f = linspace(h6, hf, Nseg).';                                                    % h vektörü
T_6f = PropsSI('T','P',Pevap,'H',h_6f,fluid);                                       % T(P,H)
s_6f = PropsSI('S','P',Pevap,'H',h_6f,fluid);                                       % s(P,H)
T_6f = T_6f(:); s_6f = s_6f(:);                                                     % Koruma

% hf -> hg (evaporation)
Q_fg = linspace(0, 1, Nseg).';                                                      % Q vektörü
T_fg = PropsSI('T','P',Pevap,'Q',Q_fg,fluid);                                       % T(P,Q)
s_fg = PropsSI('S','P',Pevap,'Q',Q_fg,fluid);                                       % s(P,Q)
T_fg = T_fg(:); s_fg = s_fg(:);                                                     % Koruma

% hg -> h3 (corr)
T_3corr = []; s_3corr = [];                                                         % Varsayılan boş
if abs(h3 - hg) > 50                                                                % Eşik
    nCorr   = max(10, round(Nseg/3));                                               % Nokta sayısı
    h_g3    = linspace(hg, h3, nCorr).';                                            % h vektörü
    T_3corr = PropsSI('T','P',Pevap,'H',h_g3,fluid);                                % T(P,H)
    s_3corr = PropsSI('S','P',Pevap,'H',h_g3,fluid);                                % s(P,H)
    T_3corr = T_3corr(:); s_3corr = s_3corr(:);                                     % Koruma
end

% --- 4 -> 5 (Kondenser)
h_g_cond = PropsSI('H','P',Pcond,'Q',1,fluid);                                      % sat buhar h @ Pcond
h_f_cond = PropsSI('H','P',Pcond,'Q',0,fluid);                                      % sat sıvı  h @ Pcond

% 4 -> g (desuperheat)
T_4g = []; s_4g = [];                                                               % Varsayılan boş
if h4 > h_g_cond + 50                                                               % Eşik
    h_4g = linspace(h4, h_g_cond, Nseg).';                                          % h vektörü
    T_4g = PropsSI('T','P',Pcond,'H',h_4g,fluid);                                   % T(P,H)
    s_4g = PropsSI('S','P',Pcond,'H',h_4g,fluid);                                   % s(P,H)
    T_4g = T_4g(:); s_4g = s_4g(:);                                                 % Koruma
end

% g -> f (condensation)
Q_gf = linspace(1, 0, Nseg).';                                                      % Q vektörü
T_gf = PropsSI('T','P',Pcond,'Q',Q_gf,fluid);                                       % T(P,Q)
s_gf = PropsSI('S','P',Pcond,'Q',Q_gf,fluid);                                       % s(P,Q)
T_gf = T_gf(:); s_gf = s_gf(:);                                                     % Koruma

% f -> 5 (corr)
T_5corr = []; s_5corr = [];                                                         % Varsayılan boş
if abs(h5 - h_f_cond) > 50                                                         % Eşik
    nCorr   = max(10, round(Nseg/3));                                               % Nokta sayısı
    h_f5    = linspace(h_f_cond, h5, nCorr).';                                      % h vektörü
    T_5corr = PropsSI('T','P',Pcond,'H',h_f5,fluid);                                % T(P,H)
    s_5corr = PropsSI('S','P',Pcond,'H',h_f5,fluid);                                % s(P,H)
    T_5corr = T_5corr(:); s_5corr = s_5corr(:);                                     % Koruma
end

% =========================
% ÇİZİM (SAFE handle pick)
% =========================
figure;                                                                              % Figür aç

h = gobjects(0);                                                                     % Legend handle listesi
L = {};                                                                              % Legend label listesi

% --- Dome sol
hp = plot(dome_sL(dome_maskL)/1000, dome_Tv(dome_maskL)-273.15,'LineWidth',1.2);     % Dome sol çiz
hold on;                                                                             % Üstüne çizime izin ver
h(end+1) = hp(1);                                                                    % Çoklu handle dönerse ilkini al
L{end+1} = 'Saturation liquid';                                                      % Legend etiketi

% --- Dome sağ
hp = plot(dome_sV(dome_maskV)/1000, dome_Tv(dome_maskV)-273.15,'LineWidth',1.2);     % Dome sağ çiz
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Saturation vapor';                                                       % Legend etiketi

% --- 5->6 pompa
hp = plot(s_56/1000, T_56-273.15,'LineWidth',1.8);                                   % Pompa eğrisi
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Pump (5→6)';                                                              % Etiket

% --- 6->f preheat
hp = plot(s_6f/1000, T_6f-273.15,'LineWidth',1.8);                                   % Preheat eğrisi
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Preheat (6→f)';                                                           % Etiket

% --- f->g evaporation
hp = plot(s_fg/1000, T_fg-273.15,'LineWidth',1.8);                                   % Evaporation eğrisi
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Evaporation (f→g)';                                                       % Etiket

% --- g->3 corr (varsa)
if ~isempty(T_3corr)
    hp = plot(s_3corr/1000, T_3corr-273.15,'LineWidth',1.8);                         % Düzeltme eğrisi
    h(end+1) = hp(1);                                                                % İlk handle
    L{end+1} = 'Evap corr (g→3)';                                                    % Etiket
end

% --- 3->4 türbin düz çizgi (PropsSI yok → hızlı)
hp = plot([s3 s4]/1000, [T3 T4]-273.15,'LineWidth',1.8);                             % Türbin doğrusu
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Turbine (3→4)';                                                           % Etiket

% --- 4->g desuperheat (varsa)
if ~isempty(T_4g)
    hp = plot(s_4g/1000, T_4g-273.15,'LineWidth',1.8);                               % Desuperheat eğrisi
    h(end+1) = hp(1);                                                                % İlk handle
    L{end+1} = 'Desuperheat (4→g)';                                                  % Etiket
end

% --- g->f condensation
hp = plot(s_gf/1000, T_gf-273.15,'LineWidth',1.8);                                   % Yoğuşma eğrisi
h(end+1) = hp(1);                                                                    % İlk handle
L{end+1} = 'Condensation (g→f)';                                                      % Etiket

% --- f->5 corr (varsa)
if ~isempty(T_5corr)
    hp = plot(s_5corr/1000, T_5corr-273.15,'LineWidth',1.8);                         % Düzeltme eğrisi
    h(end+1) = hp(1);                                                                % İlk handle
    L{end+1} = 'Cond corr (f→5)';                                                    % Etiket
end

% --- State marker’ları (legend’a eklemeden)
plot([s3 s4 s5 s6]/1000, [T3 T4 T5 T6]-273.15,'o','LineWidth',1.8);                  % Nokta marker

xlabel('Entropy s [kJ/kg-K]');                                                       % X etiketi
ylabel('Temperature T [°C]');                                                        % Y etiketi
title(sprintf('ORC T-s Diagram (%s) - FAST SAFE', fluid));                           % Başlık
grid on;                                                                             % Izgara

legend(h, L, 'Location','best');                                                     % Legend (dinamik)
end


%% ========================= PTC RESIDUALS + SYLTHERM PROPS (SENİN KOD) =========================
function F = residuals_ptc(x, Gb, Vwind, Tam, Tin, V_Lmin, R, ptc, sigma)
Tr   = x(1);
Tc   = x(2);
Tout = x(3);

Tfm = 0.5*(Tin+Tout);
[rho, cp, k, mu] = syltherm800_props(Tfm);

V_m3s = V_Lmin*1e-3/60;
mdot  = rho*V_m3s;

Re = 4*mdot/(pi*ptc.Dri*mu);
Pr = mu*cp/k;

Nu0 = 0.023*(Re^0.8)*(Pr^0.4);
Nu  = R*Nu0;
h   = Nu*k/ptc.Dri;

Qs   = ptc.Aa*Gb;
Qabs = Qs*ptc.eta_opt;

Qu = mdot*cp*(Tout-Tin);

eps_r = 0.05599 + 1.039e-4*Tr + 2.249e-7*(Tr^2);
Tsky  = 0.0553*(Tam^1.5);
hout  = 4*(Vwind^0.58)*(ptc.Dco^(-0.42));

denom = (1/eps_r) + ((1-ptc.eps_c)/ptc.eps_c)*(ptc.Aro/ptc.Aci);
Qloss_r2c = ptc.Aro*sigma*(Tr^4 - Tc^4)/denom;

Qloss_c2a = ptc.Aco*hout*(Tc - Tam) + ptc.Aco*sigma*ptc.eps_c*(Tc^4 - Tsky^4);
Qu_conv = h*ptc.Ari*(Tr - Tfm);

F = zeros(3,1);
F(1) = Qloss_r2c - Qloss_c2a;
F(2) = Qu - Qu_conv;
F(3) = Qabs - Qu - Qloss_r2c;
end

function [rho, cp, k, mu] = syltherm800_props(TK)
TC = TK - 273.15;

data = [ ...
    -40 1.506 990.61 0.1463 51.05
    -30 1.523 981.08 0.1444 35.45
    -20 1.540 971.68 0.1425 25.86
    -10 1.557 962.37 0.1407 19.61
      0 1.574 953.16 0.1388 15.33
     10 1.591 944.04 0.1369 12.27
     20 1.608 934.99 0.1350 10.03
     30 1.625 926.00 0.1331  8.32
     40 1.643 917.07 0.1312  7.00
     50 1.660 908.18 0.1294  5.96
     60 1.677 899.32 0.1275  5.12
     70 1.694 890.49 0.1256  4.43
     80 1.711 881.68 0.1237  3.86
     90 1.728 872.86 0.1218  3.39
    100 1.745 864.05 0.1200  2.99
    110 1.762 855.21 0.1181  2.65
    120 1.779 846.35 0.1162  2.36
    130 1.796 837.46 0.1143  2.11
    140 1.813 828.51 0.1124  1.89
    150 1.830 819.51 0.1106  1.70
    160 1.847 810.45 0.1087  1.54
    170 1.864 801.31 0.1068  1.39
    180 1.882 792.08 0.1049  1.26
    190 1.899 782.76 0.1030  1.15
    200 1.916 773.33 0.1012  1.05
    210 1.933 763.78 0.0993  0.96
    220 1.950 754.11 0.0974  0.88
    230 1.967 744.30 0.0955  0.81
    240 1.984 734.35 0.0936  0.74
    250 2.001 724.24 0.0918  0.69
    260 2.018 713.96 0.0899  0.63
    270 2.035 703.51 0.0880  0.59
    280 2.052 692.87 0.0861  0.54
    290 2.069 682.03 0.0842  0.50
    300 2.086 670.99 0.0824  0.47
    310 2.104 659.73 0.0805  0.44
    320 2.121 648.24 0.0786  0.41
    330 2.138 636.52 0.0767  0.38
    340 2.155 624.55 0.0748  0.36
    350 2.172 612.33 0.0729  0.33
    360 2.189 599.83 0.0711  0.31
    370 2.206 587.07 0.0692  0.29
    380 2.223 574.01 0.0673  0.28
    390 2.240 560.66 0.0654  0.26
    400 2.257 547.00 0.0635  0.25
];

T = data(:,1);
cp_kJ = interp1(T, data(:,2), TC, 'linear', 'extrap');
rho   = interp1(T, data(:,3), TC, 'linear', 'extrap');
k     = interp1(T, data(:,4), TC, 'linear', 'extrap');
mu_mPa= interp1(T, data(:,5), TC, 'linear', 'extrap');

cp = cp_kJ*1000;                                                                   % [J/kgK]
mu = mu_mPa*1e-3;                                                                  % [Pa.s]
end


function cond_out = condenser_aircooled_UA_and_fan(orc, out, cond)
% Air-cooled condenser için UA_required ve fan gücü hesapla.
% Varsayım:
% - Refrigerant kondenzasyon sıcaklığı ~ Tcond_sat (Pcond’de)
% - Sıcak taraf faz değişimi: C_r ~ 0 (sıcak taraf kapasite sonsuz)
% - ε–NTU: ε = 1 - exp(-NTU)
% - Q = ε * Cmin * (Tcond - Tair_in)

cond_out = struct();                                                               % Çıktı

% ORC çözümü başarılı değilse boş dön
if ~out.ok
    cond_out.ok  = false;
    cond_out.msg = 'ORC not solved -> condenser skipped.';
    return
end

fluid = orc.fluid;                                                                 % ORC akışkanı
Pcond = orc.P_cond_bar * 1e5;                                                      % [Pa]

Tcond_sat_K = PropsSI('T','P',Pcond,'Q',0,fluid);                                  % Kondenzasyon sıcaklığı [K]
Qcon_W = out.Qcon_kW * 1000;                                                       % Kondenser yükü [W]

Tair_in_K = cond.Tair_in_C + 273.15;                                               % Hava giriş [K]
mdot_air  = cond.mdot_air_kg_s;                                                    % Hava debisi [kg/s]
cp_air    = cond.cp_air_JkgK;                                                      % cp [J/kgK]

Cmin = mdot_air * cp_air;                                                          % Hava kapasite oranı [W/K]
Qmax_W = Cmin * (Tcond_sat_K - Tair_in_K);                                         % Maks mümkün ısı [W]

cond_out.Tcond_sat_C = Tcond_sat_K - 273.15;                                       % [°C]
cond_out.Qcon_kW     = Qcon_W/1000;                                                % [kW]
cond_out.Qmax_kW     = Qmax_W/1000;                                                % [kW]

if Qcon_W <= 0
    cond_out.ok  = false;
    cond_out.msg = 'Invalid Qcon (<=0).';
    return
end
if Qcon_W >= Qmax_W
    cond_out.ok  = false;
    cond_out.msg = sprintf('Condenser infeasible: Qcon=%.2f kW >= Qmax=%.2f kW.', Qcon_W/1000, Qmax_W/1000);
    return
end

epsilon = Qcon_W / Qmax_W;                                                         % ε
NTU = -log(1 - epsilon);                                                           % ε = 1-exp(-NTU) => NTU=-ln(1-ε)
UA_WK = NTU * Cmin;                                                                % UA

% Hava çıkış sıcaklığı (enerji dengesi)
Tair_out_K = Tair_in_K + Qcon_W / Cmin;                                            % [K]

% ---- Hava tarafı basınç kaybı ve fan gücü ----
rho_air = PropsSI('D','T',Tair_in_K,'P',cond.Pamb_Pa,'Air');                       % Yoğunluk [kg/m3]
cond_out.rho_air = rho_air;                                                        % Kaydet

dp_air = NaN;                                                                      % Δp

if strcmpi(cond.dp_model, 'K_dp')
    % Basit temsil: Δp = K*(0.5*rho*V^2)
    dp_air = cond.K_dp * (0.5 * rho_air * cond.V_face_ms^2);                       % [Pa]
elseif strcmpi(cond.dp_model, 'yumrutas_bank')
    % Yumrutaş (2002) fin-tube bank basınç kaybı formu (parametrik)
    % Δp = (G^2 * v_in /2) * [ (1+σ^2)*(v_out/v_in - 1) + f*(A/A_ff)*(v_m/v_in) ]
    sigma_b = cond.bank.sigma;
    f_b     = cond.bank.f;
    A       = cond.bank.A;
    A_ff    = cond.bank.A_ff;
    G       = cond.bank.G_kg_m2s;
    v_in    = 1/rho_air;
    v_out   = v_in;                                                                % İlk yaklaşım: çok küçük ısınma -> v_out≈v_in
    v_m     = v_in;
    dp_air  = (G^2 * v_in / 2) * ( (1+sigma_b^2)*(v_out/v_in - 1) + f_b*(A/A_ff)*(v_m/v_in) );
else
    dp_air = NaN;
end

cond_out.dp_air_Pa = dp_air;                                                       % Kaydet

% Yumrutaş (2002) fan özgül işi yaklaşımı:
% w_fan ≈ (Δp / ρ_in) / η_fan    (m^2/s^2 = J/kg)
% Fan gücü: Wfan = mdot_air * w_fan
w_fan_Jkg = (dp_air / rho_air) / max(cond.eta_fan,1e-6);                           % [J/kg]
Wfan_W    = mdot_air * w_fan_Jkg;                                                  % [W]

cond_out.epsilon   = epsilon;                                                      % eps
cond_out.NTU       = NTU;                                                          % NTU
cond_out.UA_WK     = UA_WK;                                                        % UA
cond_out.Tair_out_C = Tair_out_K - 273.15;                                         % [°C]
cond_out.Wfan_kW    = Wfan_W/1000;                                                 % [kW]
cond_out.ok         = true;                                                        % OK
cond_out.msg        = 'OK';                                                        % Mesaj
end