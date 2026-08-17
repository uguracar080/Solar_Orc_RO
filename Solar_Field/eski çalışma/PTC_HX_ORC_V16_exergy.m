%% PTC_WasteHeat_PTCPreheater_ORC_Pinch_Condenser_UA_Fan_SingleFile.m
% Amaç:
%   (A) Atık ısı (su) kaynağını parametreli tanımla (Kaska 2014 Case-1: 122.4°C, 16.23 kg/s)
%   (B) PTC sahasını (SYLTHERM 800) seri/paralel modül sayısı ile modelle
%   (C) PTC -> Atık su ön ısıtıcı eşanjörünü (counterflow) ε–NTU ile modelle:
%       - Atık su debisi sabit, hedef Tout_waste ver
%       - Hedefe ulaşmak için UA_required çöz
%       - Minimum yaklaşma sıcaklığı (ΔTmin) kontrolü yap
%   (D) Atık su (State-1) -> ORC evaporatörü (pinch point mantığı korunur)
%   (E) ORC çevrimi CoolProp PropsSI wrapper ile çöz (R245fa)
%   (F) Water-cooled condenser: verilen Qcon'u atacak UA_required bul (Tcond~sabittir)
% Gereken:
%   - PropsSI.m (CoolProp wrapper)
%   - Optimization Toolbox (fsolve/fzero)

clear; clc; close all;                                                            % Ortamı temizle
tStart = tic;                                                                     % Toplam çalışma süresi ölçümü başlat
tPreliminaries = tic;                                                             % (HIZ) Süre ölçümü başlat
%% ========================= 1) GENEL AYARLAR =========================
cfg = struct();                                                                    % Genel konfigürasyon
cfg.deltaT_pinch_K   = 6.8;                                                        % ORC evaporatör pinch yaklaşımı [K]
cfg.deltaTmin_HX_K   = 7.0;                                                        % PTC->Atık su HX minimum yaklaşma [K]
cfg.make_plots       = true;                                                       % Figür üret
cfg.show_tables      = true;                                                        % Sonuç tablolarını yazdır
cfg.verbose          = false;                                                        % Detay/bug yazdır
cfg.use_HX_preheat   = false;                                                       % true: PTC->Waste HX aktif, false: bypass (no preheat)
cfg.orc_design_mode = 'kaska_totalQ';                                               % 'pinch_only' (eski) | 'kaska_totalQ' (yeni)
cfg.max_iter_orc    = 60;                                                           % iter limiti
cfg.tol_Tout_K      = 1e-4;                                                         % Tout yakınsama toleransı [K]
cfg.tol_pinch_K     = 1e-3;                                                         % pinch toleransı [K] (opsiyonel kontrol)
cfg.do_exergy       = true;                                                       % Exergy analizi hesapla
cfg.T0_C            = 25.0;                                                       % Ölü-hâl sıcaklığı [°C]
cfg.T0_K            = cfg.T0_C + 273.15;                                          % Ölü-hâl sıcaklığı [°K]          
cfg.P0_kPa          = 101.325;                                                    % Ölü-hâl basıncı [kPa]
cfg.T_sun_K         = 5800;                                                       % Güneş efektif sıcaklığı [K] (Petela)

cfg.N_int            = 50;                                                         % (HIZ) Integral noktası (80 yerine 25 genelde yeterli)
cfg.use_cpLUT        = true;                                                       % (HIZ) Su cp(T) LUT kullan (PropsSI çağrılarını azaltır)


cfg.PTC_fluid          = 'syltherm800';                                            % PTC HTF adı (senin modelin)
cfg.HX_hot_fluid       = 'syltherm800';                                            % HX hot taraf akışkanı (PTC yağı)


% OUTER LOOP: Pcond consistency

cfg.max_iter_pcond   = 3;        % dış döngü iter sayısı (2-3 yeter)
cfg.tol_pcond_bar    = 1e-3;     % Pcond yakınsama toleransı [bar]
cfg.pcond_relax      = 0.7;      % 0..1 gevşetme (1: direkt güncelle, 0.5: daha stabil)
cfg.pcond_min_bar    = 0.5;      % güvenlik alt sınır (R245fa için kaba)
cfg.pcond_max_bar    = 10.0;     % güvenlik üst sınır


% =========================
% Sirkülasyon Pompası (PTC field -> HX arası)
% =========================
cfg.use_circ_pump = true;

cfg.circ_pump = struct();
cfg.circ_pump.fluid      = 'syltherm800';  % PTC akışkanıyla aynı
cfg.circ_pump.P_loop_bar = 10.0;           % çevrim ortalama basıncı varsayımı (PropsSI için)
cfg.circ_pump.dP_Pa      = 2.0e5;          % pompanın sağladığı basınç artışı [Pa] (örn 2 bar)
cfg.circ_pump.eta_is     = 0.75;           % izentropik verim
cfg.circ_pump.eta_motor  = 0.95;           % motor/elektrik verimi (elektrik tüketimi için)

opts = optimoptions('fsolve','Display','none', ...                                 % fsolve sessiz
    'FunctionTolerance',1e-10,'StepTolerance',1e-10);                              % toleranslar

%% ========================= EVAPORATOR (FIXED UA DESIGN) =========================
evap = struct();                                  % Evaporatör tasarım yapısı
% ---- VALIDASYON TABANLI UA ----
% (Kaska Case-1 değerlerinden türetilmiş sabit fiziksel evaporatör varsayımı)
evap.UA_total_WK   = 143500;                      % [W/K]  (örnek: 143.5 kW/K) 
evap.UA_frac_evap  = 0.708;                        % %70.8 evaporation / %29.2 preheat


%% ========================= 2) ATIK ISI (SU) KAYNAĞI (PARAMETRİK) =========================
waste = struct();                                                                  % Atık ısı akışı (su)
waste.Tin_C     = 122.4;                                                           % Kaska 2014 Case-1 giriş sıcaklığı [°C] 122.4;
waste.mdot_kg_s = 16.23;                                                           % Kaska 2014 Case-1 debi [kg/s]
waste.P_bar     = 3.0;                                                             % Su basıncı varsayımı [bar] (PropsSI için)
waste.fluid     = 'Water';                                                         % CoolProp su adı
cfg.HX_cold_fluid      = waste.fluid;                                              % HX cold taraf akışkanı (Water)

% Atık su hedef evaporatör giriş sıcaklığı (State-1) – sen burayı parametrik tarayacaksın
hx = struct();                                                                     % PTC->Atık su eşanjör ayarları
hx.Tout_waste_target_C = 122.4;                                                    % HEDEF PTC-HX CIKIŞI [°C] 
hx.model              = 'epsilon_NTU_counterflow';                                 % Model tipi (şimdilik)
hx.allow_UA_solve     = true;                                                      % UA_required çöz
hx.UA_WK              = NaN;                                                       % Eğer UA biliniyorsa buraya yazılabilir

%% ========================= 2b) HIZLANDIRMA: Water cp(T) LUT (1 kez) =========================
% Amaç: pinch çözümünde binlerce PropsSI('C',...) çağrısı yerine interp kullanmak.
% Fiziksel model değişmez: cp(T,P) yine CoolProp'tan alınır, sadece önceden örneklenip interpolasyon yapılır.

cfg.cpLUT = struct();                                                              % LUT yapısı
cfg.cpLUT.enabled = false;                                                         % Varsayılan kapalı (aşağıda açılabilir)
cfg.cpLUT.fluid   = waste.fluid;                                                   % LUT akışkanı (Water)
cfg.cpLUT.P_Pa    = waste.P_bar * 1e5;                                             % LUT basıncı [Pa]

if cfg.use_cpLUT                                                                   % LUT isteniyorsa
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
orc.eta_turb   = 0.782;                                                              % Türbin izentropik verimi [-]
orc.eta_pump   = 0.70;                                                              % Pompa izentropik verimi [-]


%% ========================= 6) KONDENSER (WATER-COOLED) PARAMETRELERİ =========================
cond = struct();                                                                   % Su soğutmalı kondenser parametreleri

cond.coolant_fluid   = 'Water';                                                    % Soğutma suyu akışkanı
cond.P_cw_bar        = 2.0;                                                        % Soğutma suyu basıncı [bar] (varsayım)
cond.Tcw_in_C        = 27.0;                                                       % Soğutma suyu giriş sıcaklığı [°C] (Kaşka ile uyumlu seçebilirsin)
cond.mdot_cw_kg_s    = 104.0;                                                      % Soğutma suyu debisi [kg/s] (parametrik)
cond.UA_fixed_WK     = 472030;                                                         % [W/K] Kondenser fiziksel UA (sabit tasarım)

fprintf("Preliminaries solve time: %.2f s\n", toc(tPreliminaries));                                % (HIZ) pinch süresini yazdır

%% ========================= 7) ÇÖZÜM AKIŞI =========================
% Amaç:
%   7.1) PTC saha çözümü (seri/paralel)
%   7.1b) (Ops.) PTC->HX sirkülasyon pompası (enerji + exergy bookkeeping)
%   7.2) (Ops.) PTC->Atık su ön ısıtma eşanjörü (UA required)
%   7.3-7.4) Outer loop ile Pcond-uyumlu: Evaporatör (pinch) <-> Kondenser
%   7.5) Exergy analiz ve raporlama
%   7.6) Verim hesapları
%
% Notlar:
%   - Outer-loop içinde tablo yazdırmıyoruz (gürültü olur). Finalde basıyoruz.
%   - HX bypass ise hx_out.ok=false ve alanlar NaN/0 ile güvence altına alınır.
%   - out struct'ı, coupled solve'dan geliyor; ek bookkeeping alanlarını üstüne ekliyoruz.

%% -------------------------------------------------------------------
% 7.1) PTC SAHA ÇÖZ (SERİ/PARALEL)
% -------------------------------------------------------------------
tPTCfield = tic;
ptc_field = ptc_solve_field_series_parallel(inPTC, ptc, field, R, sigma, opts);
fprintf("PTC field solve time: %.2f s\n", toc(tPTCfield));

if cfg.show_tables
    disp("=== PTC FIELD Results ===");
    disp(ptc_field.table);
end

%% -------------------------------------------------------------------
% 7.1b) (YENİ) PTC field -> HX arası SİRKÜLASYON POMPASI (opsiyonel)
%   - PTC çıkış sıcaklığını HX girişine pompa sonrası taşıyoruz.
%   - Elektrik tüketimi Wcirc_elec_kW olarak sistem net gücünden düşülecek.
% -------------------------------------------------------------------
circ = struct();              % her durumda tanımlı kalsın (güvenli)
Th_HX_in_K = ptc_field.Th_out_K;

if cfg.use_circ_pump
    circ = circ_pump_model( ...
        cfg.circ_pump.fluid, ...
        ptc_field.Th_out_K, ...
        cfg.circ_pump.P_loop_bar*1e5, ...
        cfg.circ_pump.dP_Pa, ...
        ptc_field.mdot_hot_kg_s, ...
        cfg.circ_pump.eta_is, ...
        cfg.circ_pump.eta_motor, ...
        cfg.T0_K, cfg.P0_kPa*1000);

    if isfield(circ,'ok') && circ.ok
        Th_HX_in_K = circ.Tout_K;   % pompa sonrası HX hot giriş sıcaklığı
    else
        % pompa hesapladı ama başarısız -> bypass gibi davran
        circ.ok = false;
        circ.msg = "circ pump failed -> bypass";
        circ.Welec_W = 0;
        circ.Wshaft_W = 0;
        circ.ExD_kW = 0;
        Th_HX_in_K = ptc_field.Th_out_K;
    end
else
    % pompa tamamen kapalı -> bypass
    circ.ok = false;
    circ.msg = "circ pump bypass";
    circ.Welec_W = 0;
    circ.Wshaft_W = 0;
    circ.ExD_kW = 0;
end


%% -------------------------------------------------------------------
% 7.2) PTC -> ATIK SU ÖN ISITMA EŞANJÖRÜ (UA required) (opsiyonel)
%   - Eğer cfg.use_HX_preheat=false ise HX bypass edilir.
%   - hx_out her durumda ok/msg/Q/UA/DTmin alanları ile garanti edilir.
% -------------------------------------------------------------------
tHX = tic;

if cfg.use_HX_preheat
    hx_out = hx_counterflow_UA_required( ...
        Th_HX_in_K, ptc_field.mdot_hot_kg_s, 'syltherm800', ...                  % Hot (PTC oil)
        waste.Tin_C + 273.15, waste.mdot_kg_s, waste.fluid, waste.P_bar, ...     % Cold (waste water)
        hx.Tout_waste_target_C + 273.15, cfg.deltaTmin_HX_K);                    % Target + ΔTmin

    % Eğer fonksiyon ok/msg dönmüyorsa bile güvence
    if ~isfield(hx_out,'ok');  hx_out.ok  = true;  end
    if ~isfield(hx_out,'msg'); hx_out.msg = "OK";  end

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
    hx_out.ok          = false;                 % dispHX_Celsius vb. için önemli
    hx_out.msg         = "HX bypass (no preheat).";
end

fprintf("HX solve time: %.2f s\n", toc(tHX));

if cfg.show_tables
    disp("=== PTC -> Waste Water HX (UA solve) ===");

    % HX çıktısını tek satırlık table'a çevirip yazdır (display fonksiyonları için temiz)
    if istable(hx_out)
        HX_disp = hx_out;
    else
        HX_disp = struct2table(hx_out, "AsArray", true);
    end

    % Senin özel yazdırıcın (Celsius çeviriyor)
    dispHX_Celsius(HX_disp);
end


%% -------------------------------------------------------------------
% 7.3) ATIK SU (STATE-1) -> ORC EVAPORATÖRÜ için HOT SIDE tanımı
%   - Evap hot inlet: HX çıkışından gelir (HX bypass ise waste Tin)
% -------------------------------------------------------------------
evap_hot = struct();
evap_hot.fluid      = waste.fluid;
evap_hot.P_bar      = waste.P_bar;
evap_hot.mdot_kg_s  = waste.mdot_kg_s;
evap_hot.Tin_K      = hx_out.Tcold_out_K;    % State-1 hot inlet to evaporator


%% -------------------------------------------------------------------
% 7.3 + 7.4) OUTER LOOP: Pcond-consistent ORC + Evaporator <-> Condenser
%
% Mantık:
%   - Evaporatör+ORC solve -> Qcon, Wnet, h-state'ler Pcond'e bağlı
%   - Kondenser (UA sabit) solve -> aynı Qcon'u karşılayacak Pcond'u bulur
%   - Pcond update + yakınsama
%
% Not:
%   - Tablo basımı loop içinde yok; finalde tek sefer basılır.
% -------------------------------------------------------------------
Pcond_guess_bar = orc.P_cond_bar;
Pcond_guess_bar = min(max(Pcond_guess_bar, cfg.pcond_min_bar), cfg.pcond_max_bar);

pcond_hist = nan(cfg.max_iter_pcond,1);

tOuterAll = tic;  % outer loop toplam süre

for itP = 1:cfg.max_iter_pcond

    % (A) ORC çevrim basıncını güncelle
    orc.P_cond_bar = Pcond_guess_bar;

    % (B) Coupled Evaporator + ORC solve (pinch)
    tPinch = tic;
    out = coupled_hot_orc_evaporator_UA_solve(evap_hot, orc, evap, cfg);
    fprintf("Pinch solve time (outer it %d): %.2f s\n", itP, toc(tPinch));

    if ~isfield(out,'ok') || ~out.ok
        warning("Outer loop failed at it=%d (evaporator/orc). msg: %s", itP, string(out.msg));
        break
    end

    % Evap hot outlet: exergy / plot için kaydet
    evap_hot.Tout_K = out.Thot_out_K;

    % (C) Condenser solve: UA sabit -> gerekli Pcond'u bul
    tCond = tic;
    cond_out = condenser_watercooled_Pcond_from_fixedUA(orc, out, cond);
    fprintf("Condenser solve time (outer it %d): %.2f s\n", itP, toc(tCond));

    if ~isfield(cond_out,'ok') || ~cond_out.ok
        warning("Outer loop failed at it=%d (condenser). msg: %s", itP, string(cond_out.msg));
        break
    end

    Pcond_new_bar = cond_out.Pcond_bar;
    pcond_hist(itP) = Pcond_new_bar;

    % (D) Yakınsama kontrolü
    dP = Pcond_new_bar - Pcond_guess_bar;

    fprintf("OUTER it=%d: Pcond_guess=%.4f bar -> Pcond_new=%.4f bar (dP=%.4g bar)\n", ...
        itP, Pcond_guess_bar, Pcond_new_bar, dP);

    if abs(dP) < cfg.tol_pcond_bar
        % yakınsadı: final Pcond
        orc.P_cond_bar = Pcond_new_bar;
        break
    end

    % (E) Relaxed update (stabil)
    Pcond_guess_bar = Pcond_guess_bar + cfg.pcond_relax * dP;
    Pcond_guess_bar = min(max(Pcond_guess_bar, cfg.pcond_min_bar), cfg.pcond_max_bar);

end

fprintf("Outer loop total time: %.2f s\n", toc(tOuterAll));

% Outer loop sonrası: Pcond geçmişi / final Pcond raporu
if cfg.show_tables
    disp("=== Outer loop Pcond history ===");
    disp(pcond_hist);
    disp("=== Final Pcond (bar) used in ORC ===");
    disp(orc.P_cond_bar);
end


%% -------------------------------------------------------------------
% 7.4b) SİSTEM NET GÜÇ BOOKKEEPING (circ pump dahil)
%   - out.Wnet_kW: ORC neti (turb-pump)
%   - out.Wnet_sys_kW: sistem neti = ORC net - sirkülasyon pompası elektrik
% -------------------------------------------------------------------
Wcirc_kW = 0.0;
if isfield(circ,'ok') && circ.ok && isfield(circ,'Welec_W')
    Wcirc_kW = circ.Welec_W/1000;
end
out.Wnet_sys_kW = out.Wnet_kW - Wcirc_kW;

% ayrıca istersek out içine pompaya dair bayrakları yazalım (rapor için)
if isfield(circ,'ok') && circ.ok
    out.circ_pump_ok   = true;
    out.Wcirc_elec_kW  = Wcirc_kW;
    out.Wcirc_shaft_kW = circ.Wshaft_W/1000;
else
    out.circ_pump_ok   = false;
    out.Wcirc_elec_kW  = 0.0;
    out.Wcirc_shaft_kW = 0.0;
end


%% -------------------------------------------------------------------
% 7.4c) (ÖNEMLİ) FINAL TABLOLARI TEK SEFER BAS
%   - Eski kodda görünen iki blok buradan gelmeli:
%       1) Coupled WasteWater(1)->ORC Evaporator (Pinch) Results
%       2) Water cooled Condenser (UA required)
% -------------------------------------------------------------------
if cfg.show_tables
    disp(" ");
    disp("=== Coupled WasteWater(1)->ORC Evaporator (Pinch) Results ===");
    dispEvap_Celsius(out);

    disp(" ");
    disp("=== Water cooled Condenser (UA required) ===");
    dispCond_Celsius(cond_out);
end


%% -------------------------------------------------------------------
% 7.5) EXERGY ANALYSIS (PTC + HX + ORC + Condenser)
% -------------------------------------------------------------------
tExergy = tic;

% 7.5.1) PTC exergy (senin kuralın: HX bypass ise PTC exergy de atla)
if cfg.do_exergy && cfg.use_HX_preheat
    ex_ptc = exergy_ptc_solar_to_htf(ptc_field, inPTC, ptc, cfg);
    ex_ptc.note = "PTC exergy computed (HX preheat ON).";
else
    ex_ptc = struct();
    ex_ptc.ok = false;
    if ~cfg.do_exergy
        ex_ptc.note = "PTC exergy skipped (cfg.do_exergy=false).";
    elseif ~cfg.use_HX_preheat
        ex_ptc.note = "PTC exergy skipped (HX bypass / cfg.use_HX_preheat=false).";
    else
        ex_ptc.note = "PTC exergy skipped (unknown reason).";
    end
end

% 7.5.2) HX exergy (HX bypass ise atla)
if cfg.do_exergy && cfg.use_HX_preheat
    ex_hx = exergy_hx_two_stream(hx_out, ptc_field, waste, cfg);
    ex_hx.note = "HX exergy computed (HX preheat ON).";
else
    ex_hx = struct();
    ex_hx.ok = false;
    if ~cfg.do_exergy
        ex_hx.note = "HX exergy skipped (cfg.do_exergy=false).";
    elseif ~cfg.use_HX_preheat
        ex_hx.note = "HX exergy skipped (HX bypass / cfg.use_HX_preheat=false).";
    else
        ex_hx.note = "HX exergy skipped (unknown reason).";
    end
end

% 7.5.3) ORC + condenser exergy (tek fonksiyon)
if cfg.do_exergy
    ex_orc = exergy_analysis_system( ...
        ptc_field, inPTC, ptc, field, ...     % PTC tarafı
        hx_out, waste, evap_hot, ...          % kaynaklar + evap hot
        orc, out, cond, cond_out, cfg);       % ORC + condenser

    out.exergy = ex_orc;
end

% 7.5.4) Sistem toplamlarını birleştir
if cfg.do_exergy && isfield(out,'exergy') && isfield(out.exergy,'ok') && out.exergy.ok

    % bilgi alanları
    out.exergy.HX_preheat_enabled = logical(cfg.use_HX_preheat);

    % ORC toplam yıkım alanını standardize et
    if isfield(out.exergy,'ExD_total_kW')
        out.exergy.ExD_ORC_total_kW = out.exergy.ExD_total_kW;
    elseif ~isfield(out.exergy,'ExD_ORC_total_kW')
        out.exergy.ExD_ORC_total_kW = NaN;
    end

    % PTC katkısı
    if isfield(ex_ptc,'ok') && ex_ptc.ok
        out.exergy.ExD_PTC_kW      = getfield(ex_ptc, 'ExD_PTC_kW'); %#ok<GFLD>
        out.exergy.Ex_solar_kW     = getfield(ex_ptc, 'Ex_solar_kW'); %#ok<GFLD>
        out.exergy.Ex_HTF_gain_kW  = getfield(ex_ptc, 'Ex_HTF_gain_kW'); %#ok<GFLD>
    else
        out.exergy.ExD_PTC_kW      = NaN;
        out.exergy.Ex_solar_kW     = NaN;
        out.exergy.Ex_HTF_gain_kW  = NaN;
    end

    % HX katkısı
    if isfield(ex_hx,'ok') && ex_hx.ok && isfield(ex_hx,'ExD_HX_kW')
        out.exergy.ExD_HX_kW = ex_hx.ExD_HX_kW;
    else
        out.exergy.ExD_HX_kW = NaN;
    end

    % sirkülasyon pompası exergy
    if cfg.use_circ_pump && isfield(circ,'ok') && circ.ok
        out.exergy.Wcirc_elec_kW = circ.Welec_W/1000;
        out.exergy.ExD_circ_kW   = max(0, circ.ExD_kW);
    else
        out.exergy.Wcirc_elec_kW = 0.0;
        out.exergy.ExD_circ_kW   = 0.0;
    end

    % notları birleştir
    ptc_note = "";
    hx_note  = "";
    if isfield(ex_ptc,'note'); ptc_note = string(ex_ptc.note); end
    if isfield(ex_hx,'note');  hx_note  = string(ex_hx.note);  end
    out.exergy.PTC_HX_exergy_note = ptc_note + " | " + hx_note;

    % sistem toplam yıkım
    out.exergy.ExD_System_kW = nansum([ ...
        out.exergy.ExD_PTC_kW, ...
        out.exergy.ExD_HX_kW, ...
        out.exergy.ExD_ORC_total_kW, ...
        out.exergy.ExD_circ_kW ...
    ]);

end

fprintf("Exergy solve time: %.2f s\n", toc(tExergy));


% 7.5.5) Exergy breakdown tablosu
if cfg.show_tables && cfg.do_exergy && isfield(out,'exergy') && isfield(out.exergy,'ok') && out.exergy.ok
    disp("=== Exergy Destruction Breakdown (kW) ===");

    ExBreak = table( ...
        out.exergy.ExD_evap_kW, ...
        out.exergy.ExD_turb_kW, ...
        out.exergy.ExD_pump_kW, ...
        out.exergy.ExD_cond_kW, ...
        out.exergy.ExD_ORC_total_kW, ...
        out.exergy.Ex_rej_cond_kW, ...
        out.exergy.ExD_PTC_kW, ...
        out.exergy.ExD_HX_kW, ...
        out.exergy.ExD_circ_kW, ...
        out.exergy.ExD_System_kW, ...
        out.exergy.Ex_in_hot_kW, ...
        out.exergy.HX_preheat_enabled, ...
        out.exergy.PTC_HX_exergy_note, ...
        'VariableNames', { ...
            'ExD_evap','ExD_turb','ExD_pump','ExD_cond', ...
            'ExD_ORC_total','Ex_rej_cond', ...
            'ExD_PTC','ExD_HX','ExD_circ','ExD_System', ...
            'Ex_in_hot','HX_preheat','note' ...
        });

    disp(ExBreak);
end

% 7.5.6) Component exergy efficiencies
if cfg.show_tables && cfg.do_exergy && isfield(out,'exergy') && isfield(out.exergy,'ok') && out.exergy.ok
    compEx = exergy_component_efficiencies(ptc_field, inPTC, ptc, hx_out, waste, evap_hot, orc, out, cond, cond_out, cfg);
    disp("=== Component Exergy Efficiencies (η_ex) ===");
    disp(compEx.table);
end


%% -------------------------------------------------------------------
% 7.6) THERMAL & EXERGY EFFICIENCIES (Kaşka-style)
% -------------------------------------------------------------------
if cfg.show_tables
    eff = compute_efficiencies_kaska_style(ptc_field, inPTC, ptc, cfg, out);
    disp("=== Thermal & Exergy Efficiencies (Kaşka-style) ===");
    disp(struct2table(eff, "AsArray", true));
end

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

ptc_field.Gb_Wm2 = inPTC.Gb_Wm2;                                                   % Exergy için DNI'yi ptc_field içine kaydet
ptc_field.Aa_m2  = ptc.Aa;                                                         % Exergy için açıklık alanını da kaydet, tek modül alanı
ptc_field.Aa_total_m2 = ptc.Aa * Ns * Np;                                          % saha toplam açıklık alanı



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

hx_out.Q_W = Q_req_W;   % [W]  (exergy_hx_two_stream bunu arıyor)

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

function out = coupled_hot_orc_evaporator_UA_solve(hot, orc, evap, cfg)
% coupled_hot_orc_evaporator_UA_solve
%
% 2-ZONLU (UA tabanlı) ORC evaporatör modeli (stabil fsolve sürümü)
% ------------------------------------------------------------------------------
% Zon-1 : Evaporasyon (faz değişimi)   -> ORC tarafı ~ Tevap sabit
% Zon-2 : Preheat (sensible)           -> ORC tarafı: T6 -> Tevap
%
% Fiziksel evaporatör sabit:
%   - evap.UA_total_WK    : toplam UA [W/K]
%   - evap.UA_frac_evap   : UA'nin evaporation zonuna ayrılan oranı
%
% Pinch kısıtı (eşitlik değil):
%   Thot_pp = Tevap + ΔT_pinch
%   Thot_in > Thot_pp olmalı
%   Thot_out < Thot_pp olmalı (preheat zonu sıcaklık düşüşü)
%
% Çözüm:
%   Bilinmeyenler: x = [mdot_r; Thot_out_K]
%   Denklem-1: Q_UA_total(x) - Q_hot_available(Thot_out) = 0
%   Denklem-2: Q_evap_UA(x)  - mdot_r*(h3-hf) = 0
% ------------------------------------------------------------------------------

out = struct();                                                                    % Çıkış
out.ok  = false;                                                                   % Başlangıç
out.msg = '';                                                                      % Mesaj

try
    % -------------------------
    % 0) Girdi kontrolleri
    % -------------------------
    if ~isfield(evap,'UA_total_WK');    error('evap.UA_total_WK missing'); end
    if ~isfield(evap,'UA_frac_evap');  error('evap.UA_frac_evap missing'); end
    if ~isfield(cfg,'deltaT_pinch_K'); error('cfg.deltaT_pinch_K missing'); end
    if ~isfield(cfg,'N_int');          cfg.N_int = 25; end                         % Integral noktası default

    % -------------------------
    % 1) Hot tarafı girişleri
    % -------------------------
    Thot_in_K = hot.Tin_K;                                                        % Hot giriş [K]
    mdot_hot  = hot.mdot_kg_s;                                                     % Hot debi [kg/s]

    % -------------------------
    % 2) ORC çevrimi (state'ler)
    % -------------------------
    sp = orc_specific_cycle(orc);                                                  % State-3,4,5,6 vb.

    Pevap_Pa = orc.P_evap_bar * 1e5;                                               % Evap basıncı [Pa]
    hf = PropsSI('H','P',Pevap_Pa,'Q',0,orc.fluid);                                % Sat. sıvı h @ Pevap [J/kg]

    h3 = sp.h3;                                                                    % Sat. buhar h @ Pevap [J/kg]
    h6 = sp.h6;                                                                    % Pompa çıkışı h @ Pevap [J/kg]

    Tevap_K = sp.states(3).T_C + 273.15;                                           % Tevap [K]
    T6_K    = sp.states(6).T_C + 273.15;                                           % T6 [K]

    % -------------------------
    % 3) Pinch noktası (hot)
    % -------------------------
    Thot_pp_K = Tevap_K + cfg.deltaT_pinch_K;                                      % Pinch hot sıcaklığı [K]
    if Thot_in_K <= Thot_pp_K
        error('Pinch infeasible: Thot_in <= Tevap + ΔTpinch.');
    end

    % -------------------------
    % 4) UA dağılımı
    % -------------------------
    UA_total = evap.UA_total_WK;                                                   % Toplam UA [W/K]
    UA_evap  = UA_total * evap.UA_frac_evap;                                       % Evap zonu UA
    UA_pre   = UA_total * (1 - evap.UA_frac_evap);                                 % Preheat zonu UA

    % -------------------------
    % 5) fsolve ayarları
    % -------------------------
    if ~isfield(cfg,'max_iter_orc'); cfg.max_iter_orc = 60; end                     % iter limiti
    opt = optimoptions('fsolve','Display','none', ...
        'FunctionTolerance',1e-10,'StepTolerance',1e-10,'MaxIterations',cfg.max_iter_orc);

    % -------------------------
    % 6) Başlangıç tahmini
    % -------------------------
    mdot_r0     = 1.0;                                                             % ORC debisi ilk tahmin [kg/s]
    Thot_out0_K = max(273.15, Thot_pp_K - 15);                                      % Hot çıkış tahmini [K] (pp'den düşük)

    x0 = [mdot_r0; Thot_out0_K];                                                   % x=[mdot_r; Thot_out]

    % -------------------------
    % 7) Nonlinear sistem (2 denklem)
    % -------------------------
    fun = @(x) residual_evap2zone_UA(x, Thot_in_K, Thot_pp_K, mdot_hot, ...
                                    hot, orc, sp, Tevap_K, T6_K, hf, h3, h6, ...
                                    UA_evap, UA_pre, cfg);

    [xsol, ~, exitflag] = fsolve(fun, x0, opt);                                     % çöz

    if exitflag <= 0
        error('Evaporator solve failed (fsolve exitflag=%d).', exitflag);
    end

    mdot_r     = xsol(1);                                                          % ORC debisi [kg/s]
    Thot_out_K = xsol(2);                                                          % Hot çıkış [K]

    % -------------------------
    % 8) Çözümden sonra zon ısılarını hesapla (rapor için)
    % -------------------------
    % Zon-1 LMTD (ORC sabit Tevap)
    DT1_ev = Thot_in_K - Tevap_K;                                                  % uç 1
    DT2_ev = Thot_pp_K - Tevap_K;                                                  % uç 2
    LMTD_evap = safe_lmtd(DT1_ev, DT2_ev);                                          % güvenli LMTD
    Q_evap_UA = UA_evap * LMTD_evap;                                               % [W]

    % Zon-2 LMTD (preheat)
    DT1_pr = Thot_pp_K - Tevap_K;                                                  % uç 1
    DT2_pr = Thot_out_K - T6_K;                                                    % uç 2
    if DT2_pr <= 0
        error('Preheat infeasible: Thot_out <= T6.');
    end
    LMTD_pre = safe_lmtd(DT1_pr, DT2_pr);                                           % güvenli LMTD
    Q_pre_UA = UA_pre * LMTD_pre;                                                  % [W]

    % Hot taraftan çekilebilen ısı (integral)
    Q_hot_available = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_out_K, hot.fluid, hot.P_bar, cfg); % [W]

    % -------------------------
    % 9) ORC güç/ısılar (mdot_r ile)
    % -------------------------
    Wt_W   = mdot_r * (sp.h3 - sp.h4);                                             % Türbin [W]
    Wp_W   = mdot_r * (sp.h6 - sp.h5);                                             % Pompa  [W]
    Wnet_W = Wt_W - Wp_W;                                                          % Net    [W]

    Qev_W  = mdot_r * (sp.h3 - sp.h6);                                             % Evaporatör toplam (ORC tarafı) [W]
    Qcon_W = mdot_r * (sp.h4 - sp.h5);                                             % Kondenser yükü [W]

    % -------------------------
    % 10) out struct doldur (script + plot + flatten için gerekli)
    % -------------------------
    out.states      = sp.states;                                                   % plot_orc_ts_diagram bunu bekliyor

    out.mdot_r      = mdot_r;                                                      % [kg/s]
    out.Thot_pp_K   = Thot_pp_K;                                                    % [K]
    out.Thot_out_K  = Thot_out_K;                                                   % [K]

    out.Qevap_hot_kW = Q_evap_UA/1000;                                             % zon-1 [kW]
    out.Qpre_req_kW  = Q_pre_UA/1000;                                              % zon-2 [kW]
    out.Qhot_kW      = Q_hot_available/1000;                                       % hot çekilen [kW]

    out.Wt_kW   = Wt_W/1000;                                                       % [kW]
    out.Wp_kW   = Wp_W/1000;                                                       % [kW]
    out.Wnet_kW = Wnet_W/1000;                                                     % [kW]

    out.Qev_kW  = Qev_W/1000;                                                      % [kW]
    out.Qcon_kW = Qcon_W/1000;                                                     % [kW]

    out.eta_th  = Wnet_W / max(Qev_W,1e-9);                                        % [-]
    out.energy_closure_kW = out.Qev_kW - out.Qcon_kW - out.Wnet_kW;                % [kW] (ideal 0)

    % -------------------------
    % 11) Son fiziksel kontroller
    % -------------------------
    if Thot_out_K >= Thot_pp_K
        error('Physical check failed: Thot_out >= Thot_pp (preheat zone invalid).');
    end

    out.ok  = true;                                                                % OK
    out.msg = 'OK';                                                                % mesaj

catch ME
    out.ok  = false;                                                               % fail
    out.msg = ME.message;                                                          % hata mesajı
end
end

% ========================= ORC SPECIFIC CYCLE (SENİN KOD) =========================
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

% === Local residual function (2 eq) ==================================
function F = residual_evap2zone_UA(x, Thot_in_K, Thot_pp_K, mdot_hot, ...
                                   hot, orc, sp, Tevap_K, T6_K, hf, h3, h6, ...
                                   UA_evap, UA_pre, cfg)
% 2 bilinmeyen: x(1)=mdot_r, x(2)=Thot_out_K
% 2 denklem:
%   (1) Q_evap_UA = mdot_r*(h3-hf)
%   (2) (Q_evap_UA+Q_pre_UA) = Q_hot_available

mdot_r     = x(1);
Thot_out_K = x(2);

% --- Fiziksel sınırlar ---
mdot_r = max(mdot_r, 1e-6);
Thot_out_K = min(Thot_out_K, Thot_pp_K - 1e-6);
Thot_out_K = max(Thot_out_K, 273.15);

% =========================
% ZON-1 (EVAP)
% =========================
DT1_ev = Thot_in_K - Tevap_K;
DT2_ev = Thot_pp_K - Tevap_K;
LMTD_evap = safe_lmtd(DT1_ev, DT2_ev);
Q_evap_UA = UA_evap * LMTD_evap;

Q_evap_ORC = mdot_r * (h3 - hf);

% =========================
% ZON-2 (PREHEAT)
% =========================
DT1_pr = Thot_pp_K - Tevap_K;
DT2_pr = Thot_out_K - T6_K;

if DT2_pr <= 1e-6
    Q_pre_UA = 0;  % LMTD tanımsız -> ısıyı 0 al (fsolve uzaklaşsın)
else
    LMTD_pre = safe_lmtd(DT1_pr, DT2_pr);
    Q_pre_UA = UA_pre * LMTD_pre;
end

% =========================
% HOT TARAF TOPLAM ISI
% =========================
Q_hot_available = hot_Qdot_integral(mdot_hot, Thot_in_K, Thot_out_K, ...
                                   hot.fluid, hot.P_bar, cfg);

% =========================
% RESIDUAL (2x1)
% =========================
F1 = Q_evap_UA - Q_evap_ORC;
F2 = (Q_evap_UA + Q_pre_UA) - Q_hot_available;

F = [F1; F2];
end

% ========================= PTC RESIDUALS + SYLTHERM PROPS  =========================
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

function cond_out = condenser_watercooled_Pcond_from_fixedUA(orc, out, cond)
% condenser_watercooled_Pcond_from_fixedUA
% -------------------------------------------------------------------------
% AMAÇ:
%   - Kondenser UA sabit (cond.UA_fixed_WK)
%   - ORC'den gelen Qcon (out.Qcon_kW) biliniyor
%   - Bu Qcon'u atabilmek için gereken Tcond_sat ve buna karşılık gelen Pcond bulunur
%
% MODEL:
%   - Refrigerant tarafı Pcond'de faz değişimi: Tcond ≈ sabit (doyma sıcaklığı)
%   - Soğutma suyu sensible ısınır
%   - Cr≈0 kabulü (hot taraf faz değişimi):  ε = 1 - exp(-NTU)
%   - NTU = UA/Cmin
%   - Q = ε * Cmin * (Tcond - Tcw_in)
%   => Tcond = Tcw_in + Q / (ε*Cmin)
% -------------------------------------------------------------------------

cond_out = struct();                                             % Çıktı struct

% -------------------------
% 0) ORC çözümü kontrolü
% -------------------------
if ~out.ok
    cond_out.ok  = false;                                        % ORC çözülmediyse kondenser çözülemez
    cond_out.msg = 'ORC not solved -> condenser skipped.';
    return
end

% -------------------------
% 1) Girdileri al
% -------------------------
fluid   = orc.fluid;                                             % ORC akışkanı (örn R245fa)
Qcon_W  = out.Qcon_kW * 1000;                                    % [W] ORC'nin kondenser yükü

UA_WK   = cond.UA_fixed_WK;                                      % [W/K] sabit UA (tasarım)
Tcw_in_K = cond.Tcw_in_C + 273.15;                               % [K] soğutma suyu giriş sıcaklığı
mdot_cw  = cond.mdot_cw_kg_s;                                    % [kg/s] soğutma suyu debisi
Pcw_Pa   = cond.P_cw_bar * 1e5;                                  % [Pa] soğutma suyu basıncı
cw_fluid = cond.coolant_fluid;                                   % 'Water'

% -------------------------
% 2) Basit fiziksellik kontrolleri
% -------------------------
cond_out.Qcon_kW = Qcon_W/1000;                                  % raporlama için

if ~isfinite(UA_WK) || UA_WK <= 0
    cond_out.ok  = false;
    cond_out.msg = 'Invalid cond.UA_fixed_WK (<=0 or NaN).';
    return
end

if Qcon_W <= 0
    cond_out.ok  = false;
    cond_out.msg = 'Invalid Qcon (<=0).';
    return
end

% -------------------------
% 3) cp ve Cmin (küçük iterasyon: cp(T) değişimi için)
% -------------------------
% Not: cp su için sıcaklığa az bağlı. Yine de sağlamlık için 2-3 iterasyon iyi olur.
Tcw_out_K = Tcw_in_K + 5;                                        % [K] başlangıç tahmini (rastgele küçük artış)
cp_cw = PropsSI('C','T',Tcw_in_K,'P',Pcw_Pa,cw_fluid);            % [J/kgK] ilk cp

for it = 1:3                                                     % 3 iterasyon genelde yeterli
    Cmin = mdot_cw * cp_cw;                                      % [W/K] Cmin (faz değişimi -> Cmax→∞ varsayımı)
    NTU  = UA_WK / max(Cmin,1e-12);                              % [-] NTU = UA/Cmin (0'a bölme koruması)
    epsilon = 1 - exp(-NTU);                                     % [-] Cr≈0 için etkinlik

    % epsilon çok küçükse (UA çok düşük) çözüme gitmesin
    if epsilon <= 1e-9
        cond_out.ok  = false;
        cond_out.msg = 'epsilon ~ 0 (UA too small for given mdot_cw).';
        return
    end

    % Enerji bilançosu ile cw çıkışı (Q = Cmin*(Tcw_out-Tcw_in))
    Tcw_out_K = Tcw_in_K + Qcon_W / max(Cmin,1e-12);             % [K]

    % cp'yi ortalama sıcaklıktan güncelle (daha tutarlı)
    Tcw_avg_K = 0.5*(Tcw_in_K + Tcw_out_K);                      % [K]
    cp_cw = PropsSI('C','T',Tcw_avg_K,'P',Pcw_Pa,cw_fluid);       % [J/kgK]
end

% Son değerlerle tekrar NTU/epsilon hesapla (rapora koymak için)
Cmin    = mdot_cw * cp_cw;                                       % [W/K]
NTU     = UA_WK / max(Cmin,1e-12);                               % [-]
epsilon = 1 - exp(-NTU);                                         % [-]

% -------------------------
% 4) UA sabit iken gereken Tcond çöz
% -------------------------
% Q = ε*Cmin*(Tcond - Tcw_in)  =>  Tcond = Tcw_in + Q/(ε*Cmin)
Tcond_sat_K = Tcw_in_K + Qcon_W / max(epsilon*Cmin,1e-12);       % [K] gereken doyma sıcaklığı

% Fiziksel kontrol: yoğuşma sıcaklığı cw girişinden büyük olmalı
if Tcond_sat_K <= Tcw_in_K
    cond_out.ok  = false;
    cond_out.msg = 'Solved Tcond_sat <= Tcw_in (non-physical). Check UA/mdot_cw/Qcon.';
    return
end

% -------------------------
% 5) Tcond_sat -> Pcond dönüşümü (doyma basıncı)
% -------------------------
% Doyma: Q=0 (sat. liquid) veya Q=1 fark etmez, doyma eğrisi aynı; Q=0 seçiyoruz.
Pcond_Pa = PropsSI('P','T',Tcond_sat_K,'Q',0,fluid);             % [Pa] doyma basıncı

% -------------------------
% 6) Çıktıları doldur
% -------------------------
cond_out.UA_WK       = UA_WK;                                     % [W/K] sabit UA
cond_out.NTU         = NTU;                                       % [-]
cond_out.epsilon     = epsilon;                                   % [-]

cond_out.Tcond_sat_C = Tcond_sat_K - 273.15;                      % [°C]
cond_out.Pcond_bar   = Pcond_Pa / 1e5;                            % [bar] gereken kondenser basıncı

cond_out.Tcw_out_C   = Tcw_out_K - 273.15;                        % [°C] cw çıkışı (enerji bilançosu)

% Qmax tanımı bu modelde: Qmax = Cmin*(Tcond - Tcw_in)
Qmax_W = Cmin * (Tcond_sat_K - Tcw_in_K);                         % [W]
cond_out.Qmax_kW = Qmax_W/1000;                                   % [kW]

cond_out.ok  = true;
cond_out.msg = 'OK (fixed UA -> solved Pcond).';
end


%% =================================================================================================
%% LOCAL FUNCTION: System Exergy Analysis (PTC + HX + ORC)
%% =================================================================================================
function ex = exergy_analysis_system(ptc_field, ptc, field, hx_out, waste, evap_hot, orc, out, cond, cond_out, cfg)
% exergy_analysis_system
%   V9 yapısına uyumlu exergy hesabı:
%   ORC state'leri out.states(3,4,5,6) içindedir ve alanlar:
%   P_bar, T_C, h_kJkg, s_kJkgK
%
% Varsayımlar:
%   - KE/PE ihmal
%   - Isı transfer exergy'si için sınır sıcaklığı ~ doyma sıcaklığı kabulü
%   - Hava tarafı detayları yoksa kondenserde "minimum" yaklaşım

ex = struct();

% -------------------------
% 0) Güvenli okuma yardımcıları
% -------------------------
T0 = cfg.T0_K;
P0 = cfg.P0_kPa*1e3;   % [Pa]
fluid = orc.fluid;

if ~isfield(evap_hot,'Tout_K') || ~isfinite(evap_hot.Tout_K)                         % Tout yoksa
    ex.ok = false;                                                                   % fail
    ex.msg = "evap_hot.Tout_K missing/NaN -> cannot compute evaporator exergy.";     % mesaj
    return                                                                           % çık
end



% out.states mevcut mu?
if ~isfield(out,'states') || numel(out.states) < 6
    warning('out.states bulunamadı veya 6 state yok. Exergy hesap atlandı.');
    ex.ok = false;
    return;
end

% Her state için h,s oku (J/kg ve J/kg-K)
[h3,s3,T3K,P3Pa] = get_state_hs(out.states,3);
[h4,s4,T4K,P4Pa] = get_state_hs(out.states,4);
[h5,s5,T5K,P5Pa] = get_state_hs(out.states,5);
[h6,s6,T6K,P6Pa] = get_state_hs(out.states,6);

mdot = out.mdot_r;   % ORC kütlesel debisi [kg/s] (V9'da out.mdot_r var)

% out.Wt_kW vb. var, W değerlerini al (W)
Wt_W  = out.Wt_kW*1000;
Wp_W  = out.Wp_kW*1000;

% Isı yükleri (W)
Qev_W  = out.Qev_kW*1000;   % ORC evaporatör ısı girişi (pozitif)
Qcon_W = out.Qcon_kW*1000;  % ORC kondenser ısı atımı (pozitif)

% -------------------------
% 1) Dead-state (h0,s0) aynı akışkan için
% -------------------------
h0 = PropsSI('H','T',T0,'P',P0,fluid);
s0 = PropsSI('S','T',T0,'P',P0,fluid);

% -------------------------
% 2) Specific flow exergy (J/kg)
%    e = (h-h0) - T0*(s-s0)
% -------------------------
e3 = (h3-h0) - T0*(s3-s0);
e4 = (h4-h0) - T0*(s4-s0);
e5 = (h5-h0) - T0*(s5-s0);
e6 = (h6-h0) - T0*(s6-s0);

% Exergy rate (W)
Ex3 = mdot*e3;
Ex4 = mdot*e4;
Ex5 = mdot*e5;
Ex6 = mdot*e6;

% -------------------------
% 3) Bileşen exergy yıkımı (ExD) – işaretler pozitif olacak şekilde
% -------------------------

% 3.1 Pompa: ExD = W_in - (Ex_out - Ex_in)
ExD_pump = Wp_W - (Ex6 - Ex5);

% 3.2 Türbin: ExD = (Ex_in - Ex_out) - W_out
ExD_turb = (Ex3 - Ex4) - Wt_W;

% 3.3 Evaporatör: ExD = (Ex_in + Ex_Qin) - Ex_out
% ------------------------- EVAPORATOR: 2-STREAM EXERGY DESTRUCTION -------------------------

% Hot tarafı alan adları (senin evap_hot struct'ına göre)
Th_in_K  = evap_hot.Tin_K;                                                        % Hot inlet temperature [K]
Th_out_K = evap_hot.Tout_K;                                                       % Hot outlet temperature [K]
Ph_Pa    = evap_hot.P_bar * 1e5;                                                  % Hot pressure [Pa]
mdot_h   = evap_hot.mdot_kg_s;                                                    % Hot mass flow rate [kg/s]
fluid_hot = evap_hot.fluid;                                                       % Hot fluid name (Water)

% Hot inlet h,s [J/kg , J/kg-K]
h_h_in = PropsSI('H','T',Th_in_K ,'P',Ph_Pa,fluid_hot);                           % Hot inlet enthalpy
s_h_in = PropsSI('S','T',Th_in_K ,'P',Ph_Pa,fluid_hot);                           % Hot inlet entropy

% Hot outlet h,s [J/kg , J/kg-K]
h_h_out = PropsSI('H','T',Th_out_K,'P',Ph_Pa,fluid_hot);                          % Hot outlet enthalpy
s_h_out = PropsSI('S','T',Th_out_K,'P',Ph_Pa,fluid_hot);                          % Hot outlet entropy

% Hot dead-state h0,s0 [J/kg , J/kg-K]
h0_h = PropsSI('H','T',T0,'P',P0,fluid_hot);                                      % Dead-state enthalpy (hot)
s0_h = PropsSI('S','T',T0,'P',P0,fluid_hot);                                      % Dead-state entropy  (hot)

% Hot specific flow exergy [J/kg]
e_h_in  = (h_h_in  - h0_h) - T0*(s_h_in  - s0_h);                                 % Hot inlet specific exergy
e_h_out = (h_h_out - h0_h) - T0*(s_h_out - s0_h);                                 % Hot outlet specific exergy

% Hot exergy rates [W]
Ex_h_in  = mdot_h * e_h_in;                                                       % Hot inlet exergy rate
Ex_h_out = mdot_h * e_h_out;                                                      % Hot outlet exergy rate

% WF tarafı exergy rate'leri zaten hesaplandı: Ex6 (evap inlet), Ex3 (evap outlet)
Ex_wf_in  = Ex6;                                                                   % WF inlet exergy rate [W]
Ex_wf_out = Ex3;                                                                   % WF outlet exergy rate [W]

% Evaporatör exergy destruction (2-stream bilanço) [W]
ExD_evap = (Ex_h_in + Ex_wf_in) - (Ex_h_out + Ex_wf_out);                         % Evaporator ExD [W]


% Kaşka Case-1 için exergy input: hot akışkandan çekilen exergy [W]
Ex_in_hot = (Ex_h_in - Ex_h_out);                                                 % Exergy extracted from hot stream [W]

if ~isfinite(ExD_evap)                                                               % NaN/Inf koruması
    ExD_evap = NaN;                                                                  % işaretle
end
if isfinite(ExD_evap) && ExD_evap < 0                                                % negatif yıkım fiziksel değil
    ExD_evap = max(0, ExD_evap);                                                     % 0'a kırp (sayısal)
end


% 3.4 Kondenser (WATER-COOLED): 2-stream exergy destruction
% ExD_cond = (Ex_wf_in + Ex_cw_in) - (Ex_wf_out + Ex_cw_out)

if ~isfield(cond_out,'Tcw_out_C') || ~isfinite(cond_out.Tcw_out_C)
    ex.ok = false;
    ex.msg = "cond_out.Tcw_out_C missing/NaN -> cannot compute condenser exergy (water-cooled).";
    return
end

% WF tarafı exergy rate’leri zaten var:
%   giriş: state-4  (Ex4)
%   çıkış: state-5  (Ex5)

% Cooling-water (cw) tarafı
Tcw_in_K  = cond.Tcw_in_C + 273.15;
Tcw_out_K = cond_out.Tcw_out_C + 273.15;
Pcw_Pa    = cond.P_cw_bar * 1e5;
mdot_cw   = cond.mdot_cw_kg_s;
cw_fluid  = cond.coolant_fluid;

% cw inlet/outlet h,s
h_cw_in  = PropsSI('H','T',Tcw_in_K ,'P',Pcw_Pa,cw_fluid);
s_cw_in  = PropsSI('S','T',Tcw_in_K ,'P',Pcw_Pa,cw_fluid);
h_cw_out = PropsSI('H','T',Tcw_out_K,'P',Pcw_Pa,cw_fluid);
s_cw_out = PropsSI('S','T',Tcw_out_K,'P',Pcw_Pa,cw_fluid);

% cw dead-state
h0_cw = PropsSI('H','T',T0,'P',P0,cw_fluid);
s0_cw = PropsSI('S','T',T0,'P',P0,cw_fluid);

% cw specific flow exergy
e_cw_in  = (h_cw_in  - h0_cw) - T0*(s_cw_in  - s0_cw);
e_cw_out = (h_cw_out - h0_cw) - T0*(s_cw_out - s0_cw);

Ex_cw_in  = mdot_cw * e_cw_in;
Ex_cw_out = mdot_cw * e_cw_out;

ExD_cond = (Ex4 + Ex_cw_in) - (Ex5 + Ex_cw_out);
ExD_cond = max(0, ExD_cond);                                                       % sayısal güvenlik Sayısal negatifleri sıfıra kırp (fiziksel güven


% ================= Exergy rejection at condenser, (NOT destruction) (Kaşka, 2014) =================
% Fiziksel anlam:
% - Kondenserde çevreye atılan ısının taşıdığı exergy
% - Bu bir "destruction" değil, "lost opportunity" terimidir

Tcw_avg_K = 0.5 * (Tcw_in_K + Tcw_out_K);                                           % [K]  Isı transferi için temsilci sınır sıcaklığı (aritmetik ortalama)Mean cooling-water temperature

Qcond_W = out.Qcon_kW * 1000;                                                       % [W] Kondenserde çevreye atılan ısı (kW -> W)

Ex_rej_cond_W  = (1 - (T0 / Tcw_avg_K)) * Qcond_W;                                  % [W] Çevreye atılan ısının exergy'si: (1-T0/Tb)*Q, Exergy rejected with condenser heat
Ex_rej_cond_kW = Ex_rej_cond_W / 1000;                                              % [kW] W -> kW dönüşümü

Ex_rej_cond_kW = max(0, Ex_rej_cond_kW);                                            % [kW] Sayısal taşma vb. ile negatif çıkarsa 0'a kırp (fiziksel olarak >=0)

ex.Ex_rej_cond_kW = Ex_rej_cond_kW;                                                 % [kW] ÖNEMLİ: out yerine ex struct'ına yaz (scope problemi çözülür)


% -------------------- Total ORC exergy -------------------
ExD_total = ExD_pump + ExD_turb + ExD_evap + ExD_cond+Ex_rej_cond_kW*1000;                              % [kW] Toplam ORC exergy yıkımı


% -------------------------
% 4) Solar exergy (Petela) – ptc.A_ap ve ptc.Gb varsa
% -------------------------

Ex_solar = NaN;                                                                    % Varsayılan
eta_ex_ptc = NaN;                                                                  % PTC exergy verimi (opsiyonel)

if isfield(ptc_field,'Aa_m2') && isfield(ptc_field,'Gb_Wm2') && ptc_field.Aa_m2>0 && ptc_field.Gb_Wm2>0
    phi_petela = 1 - (4/3)*(T0/cfg.T_sun_K) + (1/3)*(T0/cfg.T_sun_K)^4;            % Petela faktörü
    
    Aap = ptc_field.Aa_m2;
    if isfield(ptc_field,'Aa_total_m2') && isfinite(ptc_field.Aa_total_m2)
        Aap = ptc_field.Aa_total_m2;
    end
    Ex_solar = Aap * ptc_field.Gb_Wm2 * phi_petela;                                 % [W]


    if isfield(ex,'Ex_HTF_gain_kW') && isfinite(ex.Ex_HTF_gain_kW) && isfinite(ex.Ex_solar_kW) && ex.Ex_solar_kW > 0
        ex.eta_ex_ptc = ex.Ex_HTF_gain_kW / ex.Ex_solar_kW;
    else
        ex.eta_ex_ptc = NaN;
    end


end

ex.Ex_solar_kW = Ex_solar/1000;                                                    % [kW]
ex.eta_ex_ptc  = eta_ex_ptc;                                                       % [-]



% ------------------------- ORC EXERGY EFFICIENCY (Kaşka Case-1) -------------------------
eta_ex_orc = NaN;
if Ex_in_hot > 0                                                                    % Hot exergy input pozitifse
    eta_ex_orc = (out.Wnet_kW*1000) / Ex_in_hot;                                   % [-]
else
    eta_ex_orc = NaN;                                                              % tanımsız
end



% -------------------------
% 5) Çıktı struct
% -------------------------
% -------------------- Store destructions into output struct --------------------------
ex.ok = true;

ex.e3 = e3; ex.e4 = e4; ex.e5 = e5; ex.e6 = e6;
ex.Ex3_W = Ex3; ex.Ex4_W = Ex4; ex.Ex5_W = Ex5; ex.Ex6_W = Ex6;


ex.ExD_pump_kW  = ExD_pump/1000;
ex.ExD_turb_kW  = ExD_turb/1000;
ex.ExD_evap_kW  = ExD_evap/1000;
ex.ExD_cond_kW  = ExD_cond/1000;
ex.ExD_total_kW = ExD_total/1000;
ex.Ex_in_hot_kW = Ex_in_hot/1000;                                                 % [kW] (Kaşka tanımı)


ex.Ex_solar_kW  = Ex_solar/1000;
ex.eta_ex_orc   = eta_ex_orc;

% ------------------------- DEBUG: EVAP EXERGY TERMS -------------------------
if cfg.verbose                                                                          % Kullanıcı verbose istiyorsa
    fprintf("\n[EX-DBG] Evap hot: Tin=%.2f C, Tout=%.2f C, P=%.3f bar, mdot=%.4f kg/s\n", ...
        Th_in_K-273.15, Th_out_K-273.15, evap_hot.P_bar, mdot_h);                      % Hot akışkan giriş/çıkış/P/mdot

    fprintf("[EX-DBG] Ex_h_in=%.3f kW, Ex_h_out=%.3f kW, (Ex_h_in-Ex_h_out)=%.3f kW\n", ...
        Ex_h_in/1000, Ex_h_out/1000, (Ex_h_in-Ex_h_out)/1000);                         % Hot exergy oranları

    fprintf("[EX-DBG] Ex_wf_in(6)=%.3f kW, Ex_wf_out(3)=%.3f kW, (Ex_wf_out-Ex_wf_in)=%.3f kW\n", ...
        Ex6/1000, Ex3/1000, (Ex3-Ex6)/1000);                                            % WF exergy değişimi

    fprintf("[EX-DBG] ExD_evap=%.3f kW\n", ExD_evap/1000);                               % Evap yıkımı
end


end

function [h_Jkg, s_JkgK, T_K, P_Pa] = get_state_hs(states, idx) % Local helper: state'den h,s,T,P oku
% states(idx).h_kJkg  -> J/kg
% states(idx).s_kJkgK -> J/kg-K
% states(idx).T_C     -> K
% states(idx).P_bar   -> Pa
st = states(idx);

h_Jkg  = st.h_kJkg  * 1000;
s_JkgK = st.s_kJkgK * 1000;
T_K    = st.T_C + 273.15;
P_Pa   = st.P_bar * 1e5;
end

function [e_Jkg, h_Jkg, s_JkgK] = exergy_state_TP(fluid, T_K, P_Pa, T0_K, P0_Pa) %% LOCAL FUNCTION: Flow Exergy from (T,P)
% Akış exergysi (kinetik/potansiyel ihmal):
%   e = (h-h0) - T0*(s-s0)
% CoolProp/PropsSI: h [J/kg], s [J/kg/K]

h_Jkg  = PropsSI('H','T',T_K,'P',P_Pa,fluid);
s_JkgK = PropsSI('S','T',T_K,'P',P_Pa,fluid);

h0 = PropsSI('H','T',T0_K,'P',P0_Pa,fluid);
s0 = PropsSI('S','T',T0_K,'P',P0_Pa,fluid);

e_Jkg = (h_Jkg - h0) - T0_K*(s_JkgK - s0);
end


function ex_ptc = exergy_ptc_solar_to_htf(ptc_field, inPTC, ptc, cfg)
%==========================================================================
% exergy_ptc_solar_to_htf
%   PTC için exergy muhasebesi (basit ama fiziksel tutarlı):
%   - Solar radiation exergy input: Petela
%   - HTF (Syltherm800) exergy gain: incompressible cp(T) yaklaşımı
%   - PTC exergy destruction: ExD_PTC = Ex_solar - Ex_HTF_gain
%
% Notlar:
%   - Basınç etkisi (HTF) ihmal: sıvı, düşük sıkıştırılabilirlik
%   - Kayıp ısının exergysi ayrıca modellenmiyor (istersen Tr/Tc ile eklenebilir)
%==========================================================================

    ex_ptc = struct();                                                             % Çıkış struct
    ex_ptc.ok = false;                                                             % Default

    %-----------------------------
    % 0) Girdi kontrolleri
    %-----------------------------
    if ~isfield(cfg,'T0_K');       error('cfg.T0_K missing'); end                   % Ölü-hâl sıcaklığı [K]
    if ~isfield(cfg,'T_sun_K');    error('cfg.T_sun_K missing'); end                % Güneş efektif sıcaklığı [K]
    if ~isfield(ptc,'Aa');         error('ptc.Aa missing (aperture area)'); end     % Aperture alanı [m2]
    if ~isfield(inPTC,'Gb_Wm2');   error('inPTC.Gb_Wm2 missing (DNI)'); end         % DNI [W/m2]
    if ~isfield(ptc_field,'Th_in_K') || ~isfield(ptc_field,'Th_out_K')
        error('ptc_field inlet/outlet temperatures missing');
    end
    if ~isfield(ptc_field,'mdot_hot_kg_s'); error('ptc_field.mdot_hot_kg_s missing'); end

    %-----------------------------
    % 1) Solar exergy input (Petela)
    %-----------------------------
    T0 = cfg.T0_K;                                                                  % Ölü-hâl T [K]
    Ts = cfg.T_sun_K;                                                               % Güneş T [K]
    phi_petela = 1 - (4/3)*(T0/Ts) + (1/3)*(T0/Ts)^4;                               % Petela faktörü [-]
    Aap = ptc.Aa;
    if isfield(ptc_field,'Aa_total_m2') && isfinite(ptc_field.Aa_total_m2)
        Aap = ptc_field.Aa_total_m2;               % ✅ saha alanı
    end
    Ex_solar_W = Aap * inPTC.Gb_Wm2 * phi_petela;


    %-----------------------------
    % 2) HTF (Syltherm800) exergy gain (incompressible cp(T))
    %    e(T) - e(T0) = ∫cp dT - T0 ∫(cp/T) dT
    %-----------------------------
    mdot = ptc_field.mdot_hot_kg_s;                                                 % HTF toplam debi [kg/s]
    Tin  = ptc_field.Th_in_K;                                                      % HTF giriş [K]
    Tout = ptc_field.Th_out_K;                                                     % HTF çıkış [K]

    % HTF specific exergy inlet/outlet [J/kg]
    e_in_Jkg  = exergy_incompressible_cpT(cfg.PTC_fluid, Tin,  T0);                 % e(Tin)
    e_out_Jkg = exergy_incompressible_cpT(cfg.PTC_fluid, Tout, T0);                 % e(Tout)

    % HTF exergy gain rate [W]
    Ex_HTF_gain_W = mdot * (e_out_Jkg - e_in_Jkg);                                  % [W]

    %-----------------------------
    % 3) PTC exergy destruction (basit)
    %-----------------------------
    ExD_PTC_W = Ex_solar_W - Ex_HTF_gain_W;                                         % [W]
    ExD_PTC_W = max(0, ExD_PTC_W);                                                  % sayısal negatifleri kırp

    %-----------------------------
    % 4) Çıkışları doldur
    %-----------------------------
    ex_ptc.ok            = true;                                                   % OK
    ex_ptc.Ex_solar_kW   = Ex_solar_W/1000;                                         % [kW]
    ex_ptc.Ex_HTF_gain_kW= Ex_HTF_gain_W/1000;                                      % [kW]
    ex_ptc.ExD_PTC_kW    = ExD_PTC_W/1000;                                          % [kW]

    
end

function e_Jkg = exergy_incompressible_cpT(fluid_tag, T_K, T0_K)
%==========================================================================
% exergy_incompressible_cpT
%   Sıvı HTF için (basınç ihmal) cp(T) ile spesifik exergy:
%       e(T) = ∫(T0->T) cp(T)dT  - T0 * ∫(T0->T) cp(T)/T dT
%   "fluid_tag" şimdilik sadece syltherm800 için kullanılıyor.
%==========================================================================

    %-----------------------------
    % 0) Integral ayarları
    %-----------------------------
    N = 80;                                                                         % Nokta sayısı (hız/kalite dengesi)
    Tvec = linspace(T0_K, T_K, N);                                                  % T0 -> T ızgara

    %-----------------------------
    % 1) cp(T) hesapla
    %-----------------------------
    cp = zeros(size(Tvec));                                                        % cp vektörü [J/kgK]
    for i = 1:numel(Tvec)                                                          % her T için
        if strcmpi(fluid_tag,'syltherm800')                                         % Syltherm800 ise
            [~, cp_i, ~, ~] = syltherm800_props(Tvec(i));                           % cp(T) [J/kgK]
            cp(i) = cp_i;                                                          % ata
        else
            error('exergy_incompressible_cpT: only syltherm800 supported for now.');
        end
    end

    %-----------------------------
    % 2) İntegralleri al
    %-----------------------------
    int_cp_dT     = trapz(Tvec, cp);                                                % ∫cp dT [J/kg]
    int_cp_overT  = trapz(Tvec, cp ./ max(Tvec,1e-12));                             % ∫cp/T dT [J/kgK]

    %-----------------------------
    % 3) Exergy
    %-----------------------------
    e_Jkg = int_cp_dT - T0_K * int_cp_overT;                                        % [J/kg]
end

function ex_hx = exergy_hx_two_stream(hx_out, ptc_field, waste, cfg)
%==========================================================================
% exergy_hx_two_stream
%   PTC yağı (hot) ↔ atık su (cold) karşı-akış HX için exergy yıkımı:
%       ExD_HX = (Ex_hot_in + Ex_cold_in) - (Ex_hot_out + Ex_cold_out)
%
% Hot side (HTF): Syltherm800 → incompressible cp(T) exergy
% Cold side (Water): CoolProp (T,P) üzerinden flow exergy
%==========================================================================

    ex_hx = struct();                                                              % Çıkış struct
    ex_hx.ok = false;                                                              % Default

    %-----------------------------
    % 0) HX bypass / başarısızlık kontrolü
    %-----------------------------
    if isempty(hx_out) || ~isstruct(hx_out) || ~isfield(hx_out,'Q_W')
        ex_hx.msg = 'hx_out missing or invalid.';                                   % mesaj
        return                                                                      % çık
    end
    if isfield(hx_out,'ok') && ~hx_out.ok
        ex_hx.msg = 'HX not ok -> exergy skipped.';                                 % mesaj
        return                                                                      % çık
    end
    if abs(hx_out.Q_W) < 1e-9
        ex_hx.ok = true;                                                           % HX yoksa yıkım 0
        ex_hx.ExD_HX_kW = 0;                                                        % [kW]
        ex_hx.msg = 'HX Q≈0 (bypass)';                                              % mesaj
        return                                                                      % çık
    end

    %-----------------------------
    % 1) Dead-state
    %-----------------------------
    T0 = cfg.T0_K;                                                                  % Ölü-hâl sıcaklığı [K]
    P0 = cfg.P0_kPa * 1e3;                                                          % Ölü-hâl basıncı [Pa]

    %-----------------------------
    % 2) Hot stream (Syltherm800) exergy rates
    %-----------------------------
    mdot_h = ptc_field.mdot_hot_kg_s;                                               % Hot mdot [kg/s]
    Th_in  = hx_out.Th_in_K;                                                        % Hot in [K]
    Th_out = hx_out.Th_out_K;                                                       % Hot out [K]

    e_h_in  = exergy_incompressible_cpT(cfg.HX_hot_fluid, Th_in,  T0);              % [J/kg]
    e_h_out = exergy_incompressible_cpT(cfg.HX_hot_fluid, Th_out, T0);              % [J/kg]

    Ex_h_in_W  = mdot_h * e_h_in;                                                   % [W]
    Ex_h_out_W = mdot_h * e_h_out;                                                  % [W]

    %-----------------------------
    % 3) Cold stream (Water) exergy rates (CoolProp flow exergy)
    %-----------------------------
    mdot_c = waste.mdot_kg_s;                                                       % Cold mdot [kg/s]
    Pc_Pa  = waste.P_bar * 1e5;                                                     % Cold pressure [Pa]
    Tc_in  = hx_out.Tcold_in_K;                                                     % Cold in [K]
    Tc_out = hx_out.Tcold_out_K;                                                    % Cold out [K]

    % Cold inlet/outlet flow exergy (J/kg) via PropsSI
    h_c_in  = PropsSI('H','T',Tc_in ,'P',Pc_Pa, waste.fluid);                       % [J/kg]
    s_c_in  = PropsSI('S','T',Tc_in ,'P',Pc_Pa, waste.fluid);                       % [J/kgK]
    h_c_out = PropsSI('H','T',Tc_out,'P',Pc_Pa, waste.fluid);                       % [J/kg]
    s_c_out = PropsSI('S','T',Tc_out,'P',Pc_Pa, waste.fluid);                       % [J/kgK]

    h0_c = PropsSI('H','T',T0,'P',P0, waste.fluid);                                 % [J/kg]
    s0_c = PropsSI('S','T',T0,'P',P0, waste.fluid);                                 % [J/kgK]

    e_c_in  = (h_c_in  - h0_c) - T0*(s_c_in  - s0_c);                               % [J/kg]
    e_c_out = (h_c_out - h0_c) - T0*(s_c_out - s0_c);                               % [J/kg]

    Ex_c_in_W  = mdot_c * e_c_in;                                                   % [W]
    Ex_c_out_W = mdot_c * e_c_out;                                                  % [W]

    %-----------------------------
    % 4) HX exergy destruction
    %-----------------------------
    ExD_HX_W = (Ex_h_in_W + Ex_c_in_W) - (Ex_h_out_W + Ex_c_out_W);                 % [W]
    ExD_HX_W = max(0, ExD_HX_W);                                                    % sayısal negatifleri kırp

    %-----------------------------
    % 5) Çıkış
    %-----------------------------
    ex_hx.ok        = true;                                                         % OK
    ex_hx.ExD_HX_kW = ExD_HX_W/1000;                                                 % [kW]
    ex_hx.msg       = 'OK';                                                         % mesaj
end

function eff = compute_efficiencies_kaska_style(ptc_field, inPTC, ptc, cfg, out)
% compute_efficiencies_kaska_style
% Kaşka mantığıyla ORC/PTC/Sistem termal + exergy verimleri (tek tablo için).
%
% Güvenli yaklaşım:
% - HX bypass ise PTC katkıları NaN bırakılır veya 0 yapılır (tercih edilebilir).
% - Exergy alanları yoksa NaN döner.

eff = struct();

% -------------------------
% 0) ORC temel büyüklükler
% -------------------------
Wnet_kW = NaN;  Qev_kW = NaN;  Qhot_kW = NaN;

if isfield(out,'Wnet_kW'); Wnet_kW = out.Wnet_kW; end
if isfield(out,'Qev_kW');  Qev_kW  = out.Qev_kW;  end
if isfield(out,'Qhot_kW'); Qhot_kW = out.Qhot_kW; end  % hot stream'den çekilen ısı (UA çözümünden)

eff.Wnet_kW = Wnet_kW;
eff.Qev_ORC_kW  = Qev_kW;
eff.Qhot_in_kW  = Qhot_kW;

% ORC thermal efficiency (zaten out.eta_th var ama garanti olsun)
if isfinite(Wnet_kW) && isfinite(Qev_kW) && Qev_kW > 0
    eff.eta_th_orc = (Wnet_kW / Qev_kW);
else
    eff.eta_th_orc = NaN;
end

% ORC exergy efficiency (Kaşka): Wnet / Ex_in_hot
if isfield(out,'exergy') && isfield(out.exergy,'Ex_in_hot_kW') && isfinite(out.exergy.Ex_in_hot_kW) && out.exergy.Ex_in_hot_kW > 0 ...
        && isfinite(Wnet_kW)
    eff.Ex_in_hot_kW = out.exergy.Ex_in_hot_kW;
    eff.eta_ex_orc   = (Wnet_kW / out.exergy.Ex_in_hot_kW);
else
    eff.Ex_in_hot_kW = NaN;
    eff.eta_ex_orc   = NaN;
end

% -------------------------
% 1) PTC thermal efficiency: Qu / (Aap*Gb)
% -------------------------
Aap_m2 = NaN; Gb = NaN; Qu_kW = NaN;

if isfield(ptc_field,'Aa_total_m2') && isfinite(ptc_field.Aa_total_m2)
    Aap_m2 = ptc_field.Aa_total_m2;
elseif isfield(ptc_field,'Aa_m2') && isfinite(ptc_field.Aa_m2)
    Aap_m2 = ptc_field.Aa_m2;
end

if isfield(inPTC,'Gb_Wm2'); Gb = inPTC.Gb_Wm2; end
if isfield(ptc_field,'Qu_total_W'); Qu_kW = ptc_field.Qu_total_W/1000; end

eff.Aap_m2 = Aap_m2;
eff.Gb_Wm2 = Gb;
eff.Qu_PTC_kW = Qu_kW;

Qsolar_in_kW = NaN;
if isfinite(Aap_m2) && isfinite(Gb) && Aap_m2>0 && Gb>0
    Qsolar_in_kW = (Aap_m2*Gb)/1000;
end
eff.Qsolar_in_kW = Qsolar_in_kW;

if isfinite(Qu_kW) && isfinite(Qsolar_in_kW) && Qsolar_in_kW>0
    eff.eta_th_ptc = Qu_kW / Qsolar_in_kW;
else
    eff.eta_th_ptc = NaN;
end

% -------------------------
% 2) PTC exergy efficiency: Ex_HTF_gain / Ex_solar
% -------------------------
% Not: exergy_ptc_solar_to_htf() zaten Ex_solar_kW ve Ex_HTF_gain_kW üretiyor.
% Sen bunları out.exergy içine yazıyorsun: Ex_solar_kW, Ex_HTF_gain_kW.
Ex_solar_kW    = NaN;
Ex_HTF_gain_kW = NaN;

if isfield(out,'exergy')
    if isfield(out.exergy,'Ex_solar_kW');    Ex_solar_kW    = out.exergy.Ex_solar_kW; end
    if isfield(out.exergy,'Ex_HTF_gain_kW'); Ex_HTF_gain_kW = out.exergy.Ex_HTF_gain_kW; end
end

eff.Ex_solar_kW = Ex_solar_kW;
eff.Ex_HTF_gain_kW = Ex_HTF_gain_kW;

if isfinite(Ex_solar_kW) && Ex_solar_kW>0 && isfinite(Ex_HTF_gain_kW)
    eff.eta_ex_ptc = Ex_HTF_gain_kW / Ex_solar_kW;   % ✅ doğru tanım
else
    eff.eta_ex_ptc = NaN;
end

% -------------------------
% 3) Sistem verimleri
% -------------------------
% Sistem termal: Wnet / (Qhot_in + Qsolar_in)  (PTC aktifse)
Qin_sys_kW = NaN;

if cfg.use_HX_preheat
    % PTC sahası var kabul: güneş girdisi dahil
    if isfinite(Qhot_kW) && isfinite(Qsolar_in_kW)
        Qin_sys_kW = Qhot_kW + Qsolar_in_kW;
    end
else
    % HX bypass (yalnız atık ısı): sadece hot stream ısı girdisi
    Qin_sys_kW = Qhot_kW;
end

eff.Qin_sys_kW = Qin_sys_kW;

if isfinite(Wnet_kW) && isfinite(Qin_sys_kW) && Qin_sys_kW>0
    eff.eta_th_sys = Wnet_kW / Qin_sys_kW;
else
    eff.eta_th_sys = NaN;
end

% Sistem exergy: Wnet / (Ex_in_hot + Ex_solar) (PTC aktifse)
Exin_sys_kW = NaN;

if cfg.use_HX_preheat
    if isfinite(eff.Ex_in_hot_kW) && isfinite(Ex_solar_kW)
        Exin_sys_kW = eff.Ex_in_hot_kW + Ex_solar_kW;
    end
else
    Exin_sys_kW = eff.Ex_in_hot_kW;
end

eff.Exin_sys_kW = Exin_sys_kW;

if isfinite(Wnet_kW) && isfinite(Exin_sys_kW) && Exin_sys_kW>0
    eff.eta_ex_sys = Wnet_kW / Exin_sys_kW;
else
    eff.eta_ex_sys = NaN;
end

end

function comp = exergy_component_efficiencies(ptc_field, inPTC, ptc, hx_out, waste, evap_hot, orc, out, cond, cond_out, cfg)
% exergy_component_efficiencies
% Bileşen bazında exergy verimleri (η_ex) + destekleyici terimler.
%
% Tanımlar (pozitif ve anlaşılır):
%  - Turbine:  η_ex,turb = W_out / (Ex_in - Ex_out)
%  - Pump:    η_ex,pump = (Ex_out - Ex_in) / W_in
%  - Evaporator (2-stream): η_ex,evap = (Ex_wf,out - Ex_wf,in) / (Ex_hot,in - Ex_hot,out)
%  - Condenser (2-stream):  η_ex,cond = (Ex_cw,out - Ex_cw,in) / (Ex_wf,in - Ex_wf,out)
%  - HX (hot->cold):        η_ex,HX   = (Ex_cold,out - Ex_cold,in) / (Ex_hot,in - Ex_hot,out)
%  - PTC:                   η_ex,PTC  = Ex_HTF_gain / Ex_solar
%  - ORC:                   η_ex,ORC  = Wnet / Ex_in_hot
%  - SYSTEM:                η_ex,SYS  = Wnet / (Ex_in_hot + Ex_solar)   (HX preheat ON ise)
%
% Not: Fan exergy dahil etmek istersen cfg.exergy_include_fan üzerinden zaten kontrol ediyorsun.

comp = struct();
T0 = cfg.T0_K;
P0 = cfg.P0_kPa * 1e3;

% -------------------------
% 0) Güvenlik kontrolleri
% -------------------------
if ~isfield(out,'exergy') || ~isfield(out.exergy,'ok') || ~out.exergy.ok
    comp.ok = false;
    comp.msg = "out.exergy missing or not ok.";
    comp.table = table();
    return
end

% ORC state exergy rate’leri (exergy_analysis_system zaten hesaplıyor)
Ex3 = NaN; Ex4 = NaN; Ex5 = NaN; Ex6 = NaN;
if isfield(out.exergy,'Ex3_W'); Ex3 = out.exergy.Ex3_W; end
if isfield(out.exergy,'Ex4_W'); Ex4 = out.exergy.Ex4_W; end
if isfield(out.exergy,'Ex5_W'); Ex5 = out.exergy.Ex5_W; end
if isfield(out.exergy,'Ex6_W'); Ex6 = out.exergy.Ex6_W; end

Wt_W = out.Wt_kW * 1000;
Wp_W = out.Wp_kW * 1000;
Wnet_W = out.Wnet_kW * 1000;

% -------------------------
% 1) TURBINE η_ex
% -------------------------
Exdrop_turb_W = (Ex3 - Ex4);
eta_ex_turb = NaN;
if isfinite(Exdrop_turb_W) && Exdrop_turb_W > 0 && isfinite(Wt_W) && Wt_W > 0
    eta_ex_turb = Wt_W / Exdrop_turb_W;
end

% -------------------------
% 2) PUMP η_ex
% -------------------------
Exrise_pump_W = (Ex6 - Ex5);
eta_ex_pump = NaN;
if isfinite(Wp_W) && Wp_W > 0 && isfinite(Exrise_pump_W) && Exrise_pump_W >= 0
    eta_ex_pump = Exrise_pump_W / Wp_W;
end

% -------------------------
% 3) EVAPORATOR η_ex (2-stream)
% -------------------------
% Hot stream: waste water (evap_hot)
Th_in_K  = evap_hot.Tin_K;
Th_out_K = evap_hot.Tout_K;
Ph_Pa    = evap_hot.P_bar * 1e5;
mdot_h   = evap_hot.mdot_kg_s;
fluid_h  = evap_hot.fluid;

% Hot exergy rates
h_h_in  = PropsSI('H','T',Th_in_K ,'P',Ph_Pa,fluid_h);
s_h_in  = PropsSI('S','T',Th_in_K ,'P',Ph_Pa,fluid_h);
h_h_out = PropsSI('H','T',Th_out_K,'P',Ph_Pa,fluid_h);
s_h_out = PropsSI('S','T',Th_out_K,'P',Ph_Pa,fluid_h);

h0_h = PropsSI('H','T',T0,'P',P0,fluid_h);
s0_h = PropsSI('S','T',T0,'P',P0,fluid_h);

e_h_in  = (h_h_in  - h0_h) - T0*(s_h_in  - s0_h);
e_h_out = (h_h_out - h0_h) - T0*(s_h_out - s0_h);

Ex_h_in  = mdot_h * e_h_in;
Ex_h_out = mdot_h * e_h_out;

Ex_in_hot_evap_W = (Ex_h_in - Ex_h_out);          % evaporatöre giren “hot exergy input”
Ex_gain_wf_evap_W = (Ex3 - Ex6);                  % WF exergy artışı

eta_ex_evap = NaN;
if isfinite(Ex_in_hot_evap_W) && Ex_in_hot_evap_W > 0 && isfinite(Ex_gain_wf_evap_W)
    eta_ex_evap = Ex_gain_wf_evap_W / Ex_in_hot_evap_W;
end

% -------------------------
% 4) CONDENSER η_ex (2-stream, water-cooled)
% -------------------------
% WF exergy drop: Ex4 -> Ex5
Ex_drop_wf_cond_W = (Ex4 - Ex5);

% Cooling-water exergy rise
Tcw_in_K  = cond.Tcw_in_C + 273.15;
Tcw_out_K = cond_out.Tcw_out_C + 273.15;
Pcw_Pa    = cond.P_cw_bar * 1e5;
mdot_cw   = cond.mdot_cw_kg_s;
cw_fluid  = cond.coolant_fluid;

h_cw_in  = PropsSI('H','T',Tcw_in_K ,'P',Pcw_Pa,cw_fluid);
s_cw_in  = PropsSI('S','T',Tcw_in_K ,'P',Pcw_Pa,cw_fluid);
h_cw_out = PropsSI('H','T',Tcw_out_K,'P',Pcw_Pa,cw_fluid);
s_cw_out = PropsSI('S','T',Tcw_out_K,'P',Pcw_Pa,cw_fluid);

h0_cw = PropsSI('H','T',T0,'P',P0,cw_fluid);
s0_cw = PropsSI('S','T',T0,'P',P0,cw_fluid);

e_cw_in  = (h_cw_in  - h0_cw) - T0*(s_cw_in  - s0_cw);
e_cw_out = (h_cw_out - h0_cw) - T0*(s_cw_out - s0_cw);

Ex_cw_in  = mdot_cw * e_cw_in;
Ex_cw_out = mdot_cw * e_cw_out;

Ex_gain_cw_W = (Ex_cw_out - Ex_cw_in);

eta_ex_cond = NaN;
if isfinite(Ex_drop_wf_cond_W) && Ex_drop_wf_cond_W > 0 && isfinite(Ex_gain_cw_W) && Ex_gain_cw_W >= 0
    eta_ex_cond = Ex_gain_cw_W / Ex_drop_wf_cond_W;
end

% -------------------------
% 5) HX η_ex  (PTC oil -> waste water)  (HX bypass ise NaN)
% -------------------------
eta_ex_hx = NaN;
Ex_drop_hot_hx_W = NaN;
Ex_gain_cold_hx_W = NaN;

if isstruct(hx_out) && isfield(hx_out,'ok') && hx_out.ok && abs(hx_out.Q_W) > 1e-9

    % Hot (Syltherm800): incompressible cp(T) exergy
    mdot_hot = ptc_field.mdot_hot_kg_s;
    e_hot_in  = exergy_incompressible_cpT(cfg.HX_hot_fluid, hx_out.Th_in_K,  T0);
    e_hot_out = exergy_incompressible_cpT(cfg.HX_hot_fluid, hx_out.Th_out_K, T0);
    Ex_hot_in  = mdot_hot * e_hot_in;
    Ex_hot_out = mdot_hot * e_hot_out;

    Ex_drop_hot_hx_W = (Ex_hot_in - Ex_hot_out);

    % Cold (Water)
    Pc_Pa = waste.P_bar * 1e5;
    mdot_c = waste.mdot_kg_s;

    h_ci  = PropsSI('H','T',hx_out.Tcold_in_K ,'P',Pc_Pa,waste.fluid);
    s_ci  = PropsSI('S','T',hx_out.Tcold_in_K ,'P',Pc_Pa,waste.fluid);
    h_co  = PropsSI('H','T',hx_out.Tcold_out_K,'P',Pc_Pa,waste.fluid);
    s_co  = PropsSI('S','T',hx_out.Tcold_out_K,'P',Pc_Pa,waste.fluid);

    h0c = PropsSI('H','T',T0,'P',P0,waste.fluid);
    s0c = PropsSI('S','T',T0,'P',P0,waste.fluid);

    e_ci = (h_ci - h0c) - T0*(s_ci - s0c);
    e_co = (h_co - h0c) - T0*(s_co - s0c);

    Ex_c_in  = mdot_c * e_ci;
    Ex_c_out = mdot_c * e_co;

    Ex_gain_cold_hx_W = (Ex_c_out - Ex_c_in);

    if isfinite(Ex_drop_hot_hx_W) && Ex_drop_hot_hx_W > 0 && isfinite(Ex_gain_cold_hx_W)
        eta_ex_hx = Ex_gain_cold_hx_W / Ex_drop_hot_hx_W;
    end
end

% -------------------------
% 6) PTC η_ex (Petela + HTF gain)
% -------------------------
eta_ex_ptc = NaN;
if isfield(out.exergy,'Ex_solar_kW') && isfield(out.exergy,'Ex_HTF_gain_kW')
    if isfinite(out.exergy.Ex_solar_kW) && out.exergy.Ex_solar_kW > 0 && isfinite(out.exergy.Ex_HTF_gain_kW)
        eta_ex_ptc = out.exergy.Ex_HTF_gain_kW / out.exergy.Ex_solar_kW;
    end
end

% -------------------------
% 7) ORC ve SYSTEM η_ex
% -------------------------
eta_ex_orc = NaN;
if isfield(out.exergy,'Ex_in_hot_kW') && isfinite(out.exergy.Ex_in_hot_kW) && out.exergy.Ex_in_hot_kW > 0
    eta_ex_orc = out.Wnet_kW / out.exergy.Ex_in_hot_kW;
end

eta_ex_sys = NaN;
Ex_in_sys_kW = NaN;
if cfg.use_HX_preheat
    if isfield(out.exergy,'Ex_in_hot_kW') && isfield(out.exergy,'Ex_solar_kW') ...
            && isfinite(out.exergy.Ex_in_hot_kW) && isfinite(out.exergy.Ex_solar_kW)
        Ex_in_sys_kW = out.exergy.Ex_in_hot_kW + out.exergy.Ex_solar_kW;
    end
else
    if isfield(out.exergy,'Ex_in_hot_kW') && isfinite(out.exergy.Ex_in_hot_kW)
        Ex_in_sys_kW = out.exergy.Ex_in_hot_kW;
    end
end
if isfinite(Ex_in_sys_kW) && Ex_in_sys_kW > 0
    eta_ex_sys = out.Wnet_kW / Ex_in_sys_kW;
end

% -------------------------
% 8) Table (satır = komponent)
% -------------------------
Component = [
    "Turbine"
    "Pump"
    "Evaporator"
    "Condenser"
    "HX (PTC↔Waste)"
    "PTC (Solar→HTF)"
    "ORC (cycle)"
    "System"
];

eta_ex = [
    eta_ex_turb
    eta_ex_pump
    eta_ex_evap
    eta_ex_cond
    eta_ex_hx
    eta_ex_ptc
    eta_ex_orc
    eta_ex_sys
];

% Destekleyici birkaç kolon (kW)
Ex_in_hot_kW = NaN(size(eta_ex));
Ex_in_hot_kW(3) = Ex_in_hot_evap_W/1000;          % evaporator hot ex input
Ex_in_hot_kW(7) = out.exergy.Ex_in_hot_kW;        % ORC hot ex input (Kaşka tanımı)
Ex_in_hot_kW(8) = Ex_in_sys_kW;                   % system ex input

W_out_kW = NaN(size(eta_ex));
W_in_kW  = NaN(size(eta_ex));
W_out_kW(1) = Wt_W/1000;
W_in_kW(2)  = Wp_W/1000;
W_out_kW(7) = Wnet_W/1000;
W_out_kW(8) = Wnet_W/1000;

ExD_kW = NaN(size(eta_ex));
if isfield(out.exergy,'ExD_turb_kW'); ExD_kW(1) = out.exergy.ExD_turb_kW; end
if isfield(out.exergy,'ExD_pump_kW'); ExD_kW(2) = out.exergy.ExD_pump_kW; end
if isfield(out.exergy,'ExD_evap_kW'); ExD_kW(3) = out.exergy.ExD_evap_kW; end
if isfield(out.exergy,'ExD_cond_kW'); ExD_kW(4) = out.exergy.ExD_cond_kW; end
if isfield(out.exergy,'ExD_HX_kW');   ExD_kW(5) = out.exergy.ExD_HX_kW; end
if isfield(out.exergy,'ExD_PTC_kW');  ExD_kW(6) = out.exergy.ExD_PTC_kW; end
if isfield(out.exergy,'ExD_ORC_total_kW'); ExD_kW(7) = out.exergy.ExD_ORC_total_kW; end
if isfield(out.exergy,'ExD_System_kW');    ExD_kW(8) = out.exergy.ExD_System_kW; end

comp.table = table(Component, eta_ex, Ex_in_hot_kW, W_in_kW, W_out_kW, ExD_kW);

comp.ok = true;
comp.msg = "OK";
end

function out = circ_pump_model(fluid, Tin_K, Pin_Pa, dP_Pa, mdot, eta_is, eta_motor, T0, P0)
% PTC field -> HX arası sirkülasyon pompası modeli (adyabatik)
% Enerji: Wdot = mdot*(h2-h1)
% Ekserji yıkımı: ExD = Welec - mdot*(psi2-psi1), psi=(h-h0)-T0(s-s0)

out = struct();
try
    P2 = Pin_Pa + dP_Pa;

    h1 = PropsSI('H','T',Tin_K,'P',Pin_Pa,fluid);
    s1 = PropsSI('S','T',Tin_K,'P',Pin_Pa,fluid);

    % izentropik çıkış entalpisi (P2, s1)
    h2s = PropsSI('H','P',P2,'S',s1,fluid);

    % gerçek çıkış entalpisi
    h2  = h1 + (h2s - h1)/eta_is;

    Tout_K = PropsSI('T','P',P2,'H',h2,fluid);
    s2     = PropsSI('S','P',P2,'H',h2,fluid);

    % Şaft işi (akışkana geçen) [W]
    Wshaft_W = mdot*(h2 - h1);

    % Elektrik tüketimi (motor dahil) [W]
    Welec_W  = Wshaft_W/eta_motor;

    % Dead-state
    h0 = PropsSI('H','T',T0,'P',P0,fluid);
    s0 = PropsSI('S','T',T0,'P',P0,fluid);

    psi1 = (h1 - h0) - T0*(s1 - s0);
    psi2 = (h2 - h0) - T0*(s2 - s0);

    Ex_in_W  = mdot*psi1;
    Ex_out_W = mdot*psi2;

    ExD_W = Welec_W - (Ex_out_W - Ex_in_W);  % adyabatik pompa için

    out.ok = true;
    out.msg = 'OK';

    out.Tin_K  = Tin_K;
    out.Tout_K = Tout_K;
    out.Pin_Pa = Pin_Pa;
    out.Pout_Pa = P2;

    out.Wshaft_W = Wshaft_W;
    out.Welec_W  = Welec_W;

    out.Ex_in_kW  = Ex_in_W/1000;
    out.Ex_out_kW = Ex_out_W/1000;
    out.ExD_kW    = ExD_W/1000;

catch ME
    out.ok = false;
    out.msg = ME.message;
    out.Tout_K = Tin_K;
    out.Welec_W = 0;
    out.ExD_kW = NaN;
end
end

%% =================================================================================================

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

function LMTD = safe_lmtd(DT1, DT2)
% LMTD = (DT1-DT2)/ln(DT1/DT2) numerik olarak DT1~DT2 durumunda patlamasın.

DT1 = max(DT1, 1e-12);                                                             % güvenlik
DT2 = max(DT2, 1e-12);                                                             % güvenlik

if abs(DT1 - DT2) < 1e-9                                                           % DT1 ~ DT2 ise
    LMTD = 0.5*(DT1 + DT2);                                                        % limit -> aritmetik ort.
else
    LMTD = (DT1 - DT2) / log(DT1/DT2);                                             % klasik LMTD
end
end

function S = exergy_flat_for_table(ex)
% exergy_flat_for_table
%   Amaç: out.exergy içindeki alanları tek satırlık tabloya çevirmek
%   Not: İlgili alan yoksa NaN/0/"" ile doldurulur ki tablo her koşulda basılabilsin.

    S = struct();                                                                  % Çıkış struct'ı (tek satır tabloya gider)

    % =========================
    % (1) Solar / verimler
    % =========================
    if isfield(ex,'Ex_solar_kW');     S.Ex_solar_kW      = ex.Ex_solar_kW;      else; S.Ex_solar_kW      = NaN; end % Solar exergy [kW]
    if isfield(ex,'Ex_HTF_gain_kW');  S.Ex_HTF_gain_kW   = ex.Ex_HTF_gain_kW;   else; S.Ex_HTF_gain_kW   = NaN; end % HTF exergy gain [kW]
    if isfield(ex,'eta_ex_ptc');      S.eta_ex_ptc       = ex.eta_ex_ptc;       else; S.eta_ex_ptc       = NaN; end % PTC exergy efficiency [-]
    if isfield(ex,'eta_ex_orc');      S.eta_ex_orc       = ex.eta_ex_orc;       else; S.eta_ex_orc       = NaN; end % ORC exergy efficiency [-]

    % =========================
    % (2) ORC bileşen ExD (kW)
    % =========================
    if isfield(ex,'ExD_evap_kW');     S.ExD_evap_kW      = ex.ExD_evap_kW;      else; S.ExD_evap_kW      = NaN; end % Evaporator ExD [kW]
    if isfield(ex,'ExD_turb_kW');     S.ExD_turb_kW      = ex.ExD_turb_kW;      else; S.ExD_turb_kW      = NaN; end % Turbine ExD [kW]
    if isfield(ex,'ExD_pump_kW');     S.ExD_pump_kW      = ex.ExD_pump_kW;      else; S.ExD_pump_kW      = NaN; end % Pump ExD [kW]
    if isfield(ex,'ExD_cond_kW');     S.ExD_cond_kW      = ex.ExD_cond_kW;      else; S.ExD_cond_kW      = NaN; end % Condenser ExD [kW]

    % =========================
    % (3) ORC toplamı (yeniden adlandırılmış)
    % =========================
    if isfield(ex,'ExD_ORC_total_kW'); S.ExD_ORC_total_kW = ex.ExD_ORC_total_kW; else; S.ExD_ORC_total_kW = NaN; end % ORC total ExD [kW]

    % =========================
    % (4) Yeni: PTC / HX / Fan / Sistem
    % =========================
    if isfield(ex,'ExD_PTC_kW');      S.ExD_PTC_kW       = ex.ExD_PTC_kW;       else; S.ExD_PTC_kW       = NaN; end % PTC ExD [kW]
    if isfield(ex,'ExD_HX_kW');       S.ExD_HX_kW        = ex.ExD_HX_kW;        else; S.ExD_HX_kW        = NaN; end % HX ExD  [kW]
    if isfield(ex,'ExD_System_kW');   S.ExD_System_kW    = ex.ExD_System_kW;    else; S.ExD_System_kW    = NaN; end % System total ExD [kW]

    % =========================
    % (5) Referans: Hot exergy input (Kaşka tanımı vb.)
    % =========================
    if isfield(ex,'Ex_in_hot_kW');    S.Ex_in_hot_kW     = ex.Ex_in_hot_kW;     else; S.Ex_in_hot_kW     = NaN; end % Hot stream exergy drop [kW]

    % =========================
    % (6) HX bypass bilgisi (rapor)
    % =========================
    if isfield(ex,'HX_preheat_enabled')
        S.HX_preheat_enabled = logical(ex.HX_preheat_enabled);                    % true/false (tercih edilen)
    else
        S.HX_preheat_enabled = false;                                             % alan yoksa false kabul et
    end

    if isfield(ex,'PTC_HX_exergy_note')
        S.PTC_HX_exergy_note = string(ex.PTC_HX_exergy_note);                     % açıklama metni
    else
        S.PTC_HX_exergy_note = "";                                                % yoksa boş
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

flat.Wturb_kW = out.Wt_kW;                                                         % Türbin gücü [kW]
flat.Wpump_kW = out.Wp_kW;                                                         % Pompa gücü  [kW]


flat.eta_th       = out.eta_th;                                                    % verim
flat.Qcon_kW      = out.Qcon_kW;                                                   % kondenser yükü

% --- EXERGY (varsa) ---
if isfield(out, 'exergy') && ~isempty(out.exergy)
    flat.eta_ex_orc        = out.exergy.eta_ex_orc;                          % ORC exergy verimi [-]
    flat.eta_ex_ptc        = out.exergy.eta_ex_ptc;                          % PTC exergy verimi [-]
    flat.Ex_in_hot_kW      = out.exergy.Ex_in_hot_kW;                        % Evaporatöre gelen sıcak akışkan exergy girişi [kW]


    flat.ExD_total_kW      = out.exergy.ExD_total_kW;                    % Toplam exergy yıkımı [kW]
    flat.ExD_evap_kW       = out.exergy.ExD_evap_kW;                     % Evaporatör exergy yıkımı [kW]
    flat.ExD_turb_kW       = out.exergy.ExD_turb_kW;                     % Türbin exergy yıkımı [kW]
    flat.ExD_pump_kW       = out.exergy.ExD_pump_kW;                     % Pompa exergy yıkımı [kW]
    flat.ExD_cond_kW       = out.exergy.ExD_cond_kW;                     % Kondenser exergy yıkımı [kW]
    flat.ExD_HX_kW         = out.exergy.ExD_HX_kW;                       % PTC->Waste HX exergy yıkımı [kW]
end

flat.ok           = out.ok;                                                        % ok
flat.msg          = string(out.msg);                                               % msg
end

function dispHX_Celsius(HX_disp)
%--------------------------------------------------------------------------
% SADECE GÖSTERİM AMAÇLI:
%   - Kelvin -> °C dönüşümü
%   - Kelvin kolonlarını kaldırır
%   - °C kolonlarını 'msg' sonrasına taşır
%   - Tek satırlık tablo olarak ekrana basar
%--------------------------------------------------------------------------

    % --- K -> °C dönüşümü
    HX_disp.Th_in_C     = HX_disp.Th_in_K    - 273.15;   % Hot in [°C]
    HX_disp.Th_out_C    = HX_disp.Th_out_K   - 273.15;   % Hot out [°C]
    HX_disp.Tcold_in_C  = HX_disp.Tcold_in_K - 273.15;   % Cold in [°C]
    HX_disp.Tcold_out_C = HX_disp.Tcold_out_K- 273.15;   % Cold out [°C]

    % --- Kelvin sütunlarını kaldır
    HX_disp = removevars( ...
        HX_disp, ...
        {'Th_in_K','Th_out_K','Tcold_in_K','Tcold_out_K'} ...
    );

    % --- °C sütunlarını 'msg' sonrasına taşı (görünüm düzeni)
    HX_disp = movevars( ...
        HX_disp, ...
        {'Th_in_C','Th_out_C','Tcold_in_C','Tcold_out_C'}, ...
        "After", "msg" ...
    );
    % --- ok ve msg en sona al
    HX_disp = movevars(HX_disp, {'ok','msg'}, "After", HX_disp.Properties.VariableNames{end});

    % --- Ekrana bas
    disp(HX_disp);

end


function plot_hx_Tx_counterflow(hx_out)
% HX T-x profili (basit lineer görselleştirme)
% HX T-x profili (basit lineer görselleştirme)

% --- SAĞLAMLIK: hx_out struct/table olabilir, ok alanı olmayabilir ---
ok = false;
msg = "";

if istable(hx_out)
    if any(strcmp(hx_out.Properties.VariableNames,'ok'))
        ok = logical(hx_out.ok(1));
    end
    if any(strcmp(hx_out.Properties.VariableNames,'msg'))
        msg = string(hx_out.msg(1));
    end
elseif isstruct(hx_out)
    if isfield(hx_out,'ok');  ok  = logical(hx_out.ok);  end
    if isfield(hx_out,'msg'); msg = string(hx_out.msg);  end
else
    ok = false;
    msg = "hx_out is neither struct nor table.";
end

if ~ok
    figure; axis off; title('HX solve failed');
    text(0.05,0.5, msg, 'Interpreter','none');
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
% plot_condenser_TQ
% Kondenser T-Q görseli:
% - Sıcak taraf (soğutucu akışkan) yaklaşık Tcond_sat'ta sabit
% - Soğuk taraf (hava veya soğutma suyu) ısınarak çıkar
%
% Bu fonksiyon hem air-cooled hem water-cooled (cw) tanımlarını destekler.
% Eğer air inlet/outlet alanları yoksa otomatik cw alanlarına düşer.

    % -------------------- Çözüm başarısızsa bilgi bas ve çık --------------------
    if ~isfield(cond_out,'ok') || ~cond_out.ok
        figure; axis off; title('Condenser solve failed');
        if isfield(cond_out,'msg')
            text(0.05,0.5, cond_out.msg, 'Interpreter','none');
        else
            text(0.05,0.5, 'Condenser solve failed (no message field).', 'Interpreter','none');
        end
        return
    end

    % -------------------- Temel büyüklükler --------------------
    Qcon_kW = cond_out.Qcon_kW;                                                    % Toplam atılan ısı [kW]
    Q = linspace(0, Qcon_kW, 200);                                                 % Kümülatif ısı ekseni [kW]

    % Yoğuşma sıcaklığı (sıcak taraf) sabit kabul edilir
    Tcond = cond_out.Tcond_sat_C * ones(size(Q));                                  % [°C] sabit hat

    % -------------------- Soğuk akışkan türünü belirle (air mı cw mı) --------------------
    has_air_in  = isfield(cond,'Tair_in_C');                                       % Girişte air var mı?
    has_air_out = isfield(cond_out,'Tair_out_C');                                  % Çıkışta air var mı?

    has_cw_in   = isfield(cond,'Tcw_in_C');                                        % Girişte cw var mı?
    has_cw_out  = isfield(cond_out,'Tcw_out_C');                                   % Çıkışta cw var mı?

    % Öncelik: air alanları tam ise air kullan, değilse cw'ye düş
    use_air = has_air_in && has_air_out;

    if use_air
        Tcold_in_C  = cond.Tair_in_C;                                              % [°C] air inlet
        Tcold_out_C = cond_out.Tair_out_C;                                         % [°C] air outlet
        cold_label  = 'Air';                                                       % Legend etiketi
        title_cold  = 'Air-cooled';                                                % Başlık etiketi
    else
        % Air yoksa cw bekleriz: inlet yoksa outlet de yoktur -> net hata mesajı
        if ~has_cw_in
            figure; axis off; title('Condenser T-Q plot error');
            text(0.05,0.5, 'Missing cond.Tcw_in_C (and no valid air inlet).', 'Interpreter','none');
            return
        end
        if ~has_cw_out
            figure; axis off; title('Condenser T-Q plot error');
            text(0.05,0.5, 'Missing cond_out.Tcw_out_C (and no valid air outlet).', 'Interpreter','none');
            return
        end

        Tcold_in_C  = cond.Tcw_in_C;                                               % [°C] cooling water inlet
        Tcold_out_C = cond_out.Tcw_out_C;                                          % [°C] cooling water outlet
        cold_label  = 'Cooling water';                                             % Legend etiketi
        title_cold  = 'Water-cooled';                                              % Başlık etiketi
    end

    % -------------------- Soğuk taraf T(Q) profili (basit lineer yaklaşım) --------------------
    % Q ekseni 0..Qcon; sıcaklık lineer artar (detaylı profil istersen UA/NTU ile çıkarılır)
    den = max(Qcon_kW, 1e-12);                                                     % 0'a bölmeyi engelle
    Tcold = Tcold_in_C + (Tcold_out_C - Tcold_in_C) * (Q/den);                     % [°C] lineer T-Q

    % -------------------- Başlık metnini güvenli kur --------------------
    % UA ve fan gücü varsa başlıkta göster, yoksa atla
    parts = {sprintf('%s condenser T-Q', title_cold)};                             % Başlık parçaları

    if isfield(cond_out,'UA_WK')
        parts{end+1} = sprintf('UA=%.1f kW/K', cond_out.UA_WK/1000);               % [kW/K]
    end

    title_str = strjoin(parts, ', ');                                              % Başlığı birleştir

    % -------------------- Çizim --------------------
    figure;
    plot(Q, Tcond,'LineWidth',1.8); hold on;                                       % Refrigerant (sabit Tcond)
    plot(Q, Tcold,'LineWidth',1.8);                                                % Soğuk akışkan (air/cw)
    xlabel('Cumulative heat rejected Q [kW]');                                     % X ekseni
    ylabel('Temperature [°C]');                                                    % Y ekseni
    title(title_str);                                                              % Başlık
    grid on;                                                                       % Izgara

    legend('Refrigerant (condensing at Tcond)', cold_label, 'Location','best');    % Legend
end


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




