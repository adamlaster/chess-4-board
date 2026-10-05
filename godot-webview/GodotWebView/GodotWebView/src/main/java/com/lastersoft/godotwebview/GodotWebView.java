package com.lastersoft.godotwebview;

import android.annotation.SuppressLint;
import android.app.Activity;
import android.app.AlertDialog;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.res.ColorStateList;
import android.content.res.Configuration;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.view.Gravity;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewConfiguration;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.Button;
import android.widget.FrameLayout;
import android.widget.LinearLayout;
import android.widget.ProgressBar;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.annotation.NonNull;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public class GodotWebView extends GodotPlugin {

    private static final String TAG = "GodotWebView";
    private FrameLayout layout = null;
    private WebView webView = null;

    // Site model for games and links
    public static class SiteEntry {
        public final String name;
        public final String url;
        public SiteEntry(String name, String url) {
            this.name = name;
            this.url = url;
        }
    }

    // Category model for grouped extra apps.
    // NOTE (Roadmap): Designed for future native runtime URL & Category management
    // (SharedPreferences JSON store + native Android AlertDialog / Godot bridge).
    public static class CategoryEntry {
        public final String title;
        public final List<SiteEntry> sites;
        public CategoryEntry(String title, List<SiteEntry> sites) {
            this.title = title;
            this.sites = sites;
        }
    }

    // Main chess sites (root menu)
    private static final List<SiteEntry> MAIN_SITES = Arrays.asList(
        new SiteEntry("♟  Chess.com", "https://www.chess.com"),
        new SiteEntry("♟  ChessKids.com", "https://www.chesskids.com"),
        new SiteEntry("♟  Lichess", "https://lichess.org/analysis"),
        new SiteEntry("♟  ChessReps", "https://chessreps.com")
    );

    // Consolidated Extra Apps menu organized by category
    private static final List<CategoryEntry> EXTRA_CATEGORIES = Arrays.asList(
        new CategoryEntry("🎲  Games", Arrays.asList(
            new SiteEntry("🐑  Colonist.io (Catan)", "https://colonist.io"),
            new SiteEntry("✏️  Dots & Boxes", "https://gametable.org/games/dots-and-boxes/"),
            new SiteEntry("🎈  PBS Kids", "https://pbskids.org"),
            new SiteEntry("🎲  247 Backgammon", "https://www.247backgammon.org"),
            new SiteEntry("🔴  247 Checkers", "https://www.247checkers.com/"),
            new SiteEntry("🌐  247 Games (All)", "https://www.247games.com")
        )),
        new CategoryEntry("📺  Video", Arrays.asList(
            new SiteEntry("▶️  YouTube", "https://www.youtube.com"),
            new SiteEntry("🦚  Peacock", "https://www.peacocktv.com"),
            new SiteEntry("🦊  Fox One", "https://www.fox.com"),
            new SiteEntry("⚾  MLB.TV", "https://www.mlb.com/tv")
        )),
        new CategoryEntry("🌐  Web", Arrays.asList(
            new SiteEntry("🔍  Google", "https://www.google.com"),
            new SiteEntry("🖼️  Google Photos", "https://photos.google.com"),
            new SiteEntry("🗺️  Google Maps", "https://www.google.com/maps")
        ))
    );

    private static int getTotalExtraAppsCount() {
        int total = 0;
        for (CategoryEntry category : EXTRA_CATEGORIES) {
            total += category.sites.size();
        }
        return total;
    }

    // Scale factor for the opened menu card and its internal controls (2.0f = 2x size)
    private static final float MENU_SCALE = 2.0f;

    // UI overlays
    private View scrimView = null;
    private LinearLayout menuCard = null;
    private Button floatingButton = null;
    private TextView slideThumb = null;
    private TextView slideLabel = null;
    private Button extraAppsToggleBtn = null;
    private ScrollView extraAppsScrollView = null;
    private final List<Runnable> categoryCollapseCallbacks = new ArrayList<>();
    private Button backButton = null;
    private Button desktopModeButton = null;
    private GradientDrawable desktopModeCircle = null;
    private View customView = null;
    private WebChromeClient.CustomViewCallback customViewCallback = null;

    // User-Agent state tracking (defaults to Desktop Mode, persisted in SharedPreferences)
    private static final String PREFS_NAME = "chess4board_prefs";
    private static final String PREF_DEFAULT_DESKTOP_MODE = "default_desktop_mode";
    private static final String DESKTOP_USER_AGENT =
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";
    private String defaultUserAgent = null;
    private boolean defaultDesktopMode = true;
    private boolean isDesktopMode = true;

    // Auto-fade timer
    private final Handler idleHandler = new Handler(Looper.getMainLooper());
    private Runnable idleFadeRunnable = null;
    private boolean isMenuOpen = false;

    // Zoom state tracking
    private final int[] zoomLevels = {75, 100, 125, 150, 200};
    private int currentZoomIndex = 1; // Default to 100%

    // 4-way 90° orientation cycle around all 4 tabletop edges
    private static final int[] ORIENTATION_CYCLE = {
            ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE,
            ActivityInfo.SCREEN_ORIENTATION_PORTRAIT,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE,
            ActivityInfo.SCREEN_ORIENTATION_REVERSE_PORTRAIT
    };
    private int currentOrientationIndex = -1;

    private boolean boardPauseListenerHooked = false;
    private int boardContextRetryCount = 0;

    public GodotWebView(Godot godot) {
        super(godot);
        prepareBoardTouchPassthrough();
    }

    @Override
    public View onMainCreate(Activity activity) {
        prepareBoardTouchPassthrough();
        return super.onMainCreate(activity);
    }

    @UsedByGodot
    public void prepareBoardTouchPassthrough() {
        try {
            Class<?> boardNativeClass = Class.forName("co.harrishill.board.core.BoardNativePlugin");
            java.lang.reflect.Method setSwallow = boardNativeClass.getMethod("setSwallowSystemTouches", boolean.class);
            setSwallow.invoke(null, false);

            java.lang.reflect.Field nativeLibLoadedField = boardNativeClass.getField("nativeLibLoaded");
            nativeLibLoadedField.setBoolean(null, false);

            Log.i(TAG, "Configured BoardNativePlugin for standard Android touch passthrough");
        } catch (Throwable t) {
            Log.w(TAG, "BoardNativePlugin touch passthrough setup skipped: " + t.getMessage());
        }

        hookBoardPauseListener();
        ensureBoardPauseContextRegistered();

        runOnUiThread(() -> {
            Activity activity = getActivity();
            if (activity != null && activity.getCurrentFocus() != null) {
                activity.getCurrentFocus().setOnTouchListener(null);
            }
        });
    }

    private void hookBoardPauseListener() {
        if (boardPauseListenerHooked) return;
        try {
            Class<?> callbackClass = Class.forName("co.harrishill.board.pausescreen.PauseResultCallbackImpl");
            Class<?> listenerInterface = Class.forName("co.harrishill.board.pausescreen.PauseResultCallbackImpl$PauseResultListener");
            java.lang.reflect.Field listenerField = callbackClass.getDeclaredField("listener");
            listenerField.setAccessible(true);
            final Object originalListener = listenerField.get(null);
            final java.lang.reflect.Method getActionTypeMethod = callbackClass.getMethod("getActionType");
            final java.lang.reflect.Method getCustomButtonIdMethod = callbackClass.getMethod("getCustomButtonId");

            Object proxyListener = java.lang.reflect.Proxy.newProxyInstance(
                    listenerInterface.getClassLoader(),
                    new Class<?>[]{listenerInterface},
                    (proxy, method, args) -> {
                        if ("onPauseResult".equals(method.getName())) {
                            try {
                                String actionType = (String) getActionTypeMethod.invoke(null);
                                String customButtonId = (String) getCustomButtonIdMethod.invoke(null);
                                Log.i(TAG, "Board pause menu action received in Java: " + actionType + " (customButtonId=" + customButtonId + ")");
                                if ("EXIT_GAME_UNSAVED".equals(actionType) || "EXIT_GAME_SAVED".equals(actionType)) {
                                    runOnUiThread(this::terminateBoardAndActivity);
                                } else if ("CUSTOM_ACTION".equals(actionType) && "open_menu".equals(customButtonId)) {
                                    runOnUiThread(this::showMenu);
                                }
                            } catch (Throwable inner) {
                                Log.e(TAG, "Error handling Board pause action in Java", inner);
                            }
                            if (originalListener != null) {
                                return method.invoke(originalListener, args);
                            }
                            return null;
                        }
                        if (originalListener != null) {
                            return method.invoke(originalListener, args);
                        }
                        return null;
                    }
            );

            java.lang.reflect.Method setListenerMethod = callbackClass.getMethod("setListener", listenerInterface);
            setListenerMethod.invoke(null, proxyListener);
            boardPauseListenerHooked = true;
            Log.i(TAG, "Hooked Board PauseResultCallbackImpl listener in Java");
        } catch (Throwable t) {
            Log.w(TAG, "Could not hook PauseResultCallbackImpl listener: " + t.getMessage());
        }
    }

    private void ensureBoardPauseContextRegistered() {
        boardContextRetryCount = 0;
        Runnable checkRunnable = new Runnable() {
            @Override
            public void run() {
                try {
                    Class<?> boardNativeClass = Class.forName("co.harrishill.board.core.BoardNativePlugin");
                    java.lang.reflect.Method areServicesReadyMethod = boardNativeClass.getMethod("areServicesReady");
                    boolean ready = (Boolean) areServicesReadyMethod.invoke(null);
                    if (ready) {
                        java.lang.reflect.Field callbackField = boardNativeClass.getDeclaredField("pauseResultCallback");
                        callbackField.setAccessible(true);
                        if (callbackField.get(null) == null) {
                            java.lang.reflect.Method setPauseContextMethod = boardNativeClass.getMethod(
                                    "setPauseContext",
                                    String.class, String.class, boolean.class,
                                    String[].class, String[].class, String[].class,
                                    String[].class, String[].class, int[].class
                            );
                            setPauseContextMethod.invoke(
                                    null,
                                    "00000000-0000-0000-0000-000000000000",
                                    "Chess 4 Board",
                                    false,
                                    new String[]{"open_menu"},
                                    new String[]{"Web Menu"},
                                    new String[]{"square"},
                                    null,
                                    null,
                                    null
                            );
                            Log.i(TAG, "Registered Board pause context with Web Menu button after SystemOverlayService bound");
                        }
                        return;
                    }
                } catch (Throwable ignored) {}

                boardContextRetryCount++;
                if (boardContextRetryCount < 50) {
                    idleHandler.postDelayed(this, 200);
                }
            }
        };
        idleHandler.postDelayed(checkRunnable, 200);
    }

    @UsedByGodot
    public void show_menu() {
        runOnUiThread(this::showMenu);
    }

    private void terminateBoardAndActivity() {
        try {
            emitSignal("quit_app_requested");
        } catch (Throwable ignored) {}

        try {
            Class<?> bridgeClass = Class.forName("co.harrishill.board.session.SessionManagerBridge");
            java.lang.reflect.Method terminateMethod = bridgeClass.getMethod("terminateApplication");
            terminateMethod.invoke(null);
            Log.i(TAG, "Called SessionManagerBridge.terminateApplication()");
        } catch (Throwable t) {
            Log.w(TAG, "SessionManagerBridge.terminateApplication() fallback: " + t.getMessage());
        }

        idleHandler.postDelayed(() -> {
            Activity activity = getActivity();
            if (activity != null && !activity.isFinishing()) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    activity.finishAndRemoveTask();
                } else {
                    activity.finish();
                }
            }
        }, 300);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "GodotWebView";
    }

    // --- REGISTER CUSTOM GODOT SIGNALS ---
    @NonNull
    @Override
    public Set getPluginSignals() {
        Set signals = new HashSet<>();
        signals.add(new SignalInfo("quit_app_requested"));
        return signals;
    }

    @SuppressLint({"SetJavaScriptEnabled", "ClickableViewAccessibility"})
    @UsedByGodot
    public void open(@NonNull String url) {
        prepareBoardTouchPassthrough();
        runOnUiThread(() -> {
            Activity activity = getActivity();
            if (activity == null) return;
            if (activity.getCurrentFocus() != null) {
                activity.getCurrentFocus().setOnTouchListener(null);
            }

            resetIdleFade(false);
            isMenuOpen = false;
            SharedPreferences prefs = activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE);
            defaultDesktopMode = prefs.getBoolean(PREF_DEFAULT_DESKTOP_MODE, true);
            isDesktopMode = defaultDesktopMode;

            if (layout == null) {
                layout = new FrameLayout(activity);
                activity.addContentView(layout, new ViewGroup.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, 
                        ViewGroup.LayoutParams.MATCH_PARENT));
            } else {
                layout.removeAllViews();
            }

            webView = new WebView(activity);

            // --- PERFORMANCE & HARDWARE ACCELERATION ---
            webView.setLayerType(View.LAYER_TYPE_HARDWARE, null);
            webView.setOverScrollMode(View.OVER_SCROLL_NEVER);
            webView.setVerticalScrollBarEnabled(false);
            webView.setHorizontalScrollBarEnabled(false);

            WebSettings settings = webView.getSettings();
            defaultUserAgent = settings.getUserAgentString();
            if (isDesktopMode) {
                settings.setUserAgentString(DESKTOP_USER_AGENT);
            }
            settings.setJavaScriptEnabled(true);
            settings.setDomStorageEnabled(true);
            settings.setDatabaseEnabled(true);
            settings.setCacheMode(WebSettings.LOAD_DEFAULT);
            settings.setUseWideViewPort(true);
            settings.setLoadWithOverviewMode(true);
            settings.setMediaPlaybackRequiresUserGesture(false);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                settings.setOffscreenPreRaster(true);
            }

            settings.setSupportZoom(true);
            settings.setBuiltInZoomControls(true);
            settings.setDisplayZoomControls(false);

            CookieManager cookieManager = CookieManager.getInstance();
            cookieManager.setAcceptCookie(true);

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                cookieManager.setAcceptThirdPartyCookies(webView, true);
            }

            webView.setWebViewClient(new WebViewClient() {
                @Override
                public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP && request != null && request.getUrl() != null) {
                        String scheme = request.getUrl().getScheme();
                        if (scheme != null && !scheme.equalsIgnoreCase("http") && !scheme.equalsIgnoreCase("https")) {
                            String fullUri = request.getUrl().toString();
                            if (fullUri.startsWith("intent://")) {
                                try {
                                    android.content.Intent intent = android.content.Intent.parseUri(fullUri, android.content.Intent.URI_INTENT_SCHEME);
                                    String fallbackUrl = intent.getStringExtra("browser_fallback_url");
                                    if (fallbackUrl != null && !fallbackUrl.isEmpty()) {
                                        view.loadUrl(fallbackUrl);
                                    }
                                } catch (Exception ignored) {}
                            }
                            return true; // Block native app schemes (vnd.youtube://, intent://, market://)
                        }
                    }
                    return false; 
                }

                @Override
                public void onPageFinished(WebView view, String url) {
                    super.onPageFinished(view, url);
                    applyCurrentZoom();
                    updateBackButtonState();
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        CookieManager.getInstance().flush();
                    }
                }
            });

            // --- LOADING PROGRESS BAR ---
            ProgressBar progressBar = new ProgressBar(activity, null, android.R.attr.progressBarStyleHorizontal);
            int progressHeight = (int) (4 * activity.getResources().getDisplayMetrics().density); // 4dp thin bar
            FrameLayout.LayoutParams progressParams = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, progressHeight);
            progressParams.gravity = Gravity.TOP;
            progressBar.setLayoutParams(progressParams);
            progressBar.setMax(100);
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                progressBar.setProgressTintList(ColorStateList.valueOf(Color.parseColor("#43A047")));
            }

            webView.setWebChromeClient(new WebChromeClient() {
                @Override
                public void onProgressChanged(WebView view, int newProgress) {
                    if (newProgress == 100) {
                        progressBar.setVisibility(View.GONE); 
                    } else {
                        progressBar.setVisibility(View.VISIBLE); 
                        progressBar.setProgress(newProgress);
                    }
                }

                @Override
                public void onPermissionRequest(final android.webkit.PermissionRequest request) {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        String[] resources = request.getResources();
                        for (String r : resources) {
                            if (android.webkit.PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID.equals(r)) {
                                request.grant(new String[]{android.webkit.PermissionRequest.RESOURCE_PROTECTED_MEDIA_ID});
                                return;
                            }
                        }
                    }
                    super.onPermissionRequest(request);
                }

                @Override
                public void onShowCustomView(View view, CustomViewCallback callback) {
                    if (customView != null) {
                        callback.onCustomViewHidden();
                        return;
                    }
                    customView = view;
                    customView.setBackgroundColor(Color.BLACK);
                    customViewCallback = callback;
                    if (webView != null) {
                        webView.setVisibility(View.GONE);
                    }
                    if (layout != null) {
                        layout.addView(customView, new FrameLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT,
                                ViewGroup.LayoutParams.MATCH_PARENT));
                        if (scrimView != null) scrimView.bringToFront();
                        if (menuCard != null) menuCard.bringToFront();
                        if (floatingButton != null) floatingButton.bringToFront();
                    }
                }

                @Override
                public void onHideCustomView() {
                    exitCustomFullscreen();
                }
            });

            // Add the WebView directly to the main FrameLayout
            layout.addView(webView, new FrameLayout.LayoutParams(
                    FrameLayout.LayoutParams.MATCH_PARENT, 
                    FrameLayout.LayoutParams.MATCH_PARENT));
                    
            layout.addView(progressBar);

            ViewGroup parentView = layout;
            while (parentView != null) {
                parentView.setClipChildren(false);
                parentView.setClipToPadding(false);
                if (parentView.getParent() instanceof ViewGroup) {
                    parentView = (ViewGroup) parentView.getParent();
                } else {
                    break;
                }
            }

            // --- METRICS & STYLING ---
            float density = activity.getResources().getDisplayMetrics().density;
            float menuDensity = density * MENU_SCALE;
            int buttonSize = (int) (58 * density);
            int controlBtnSize = (int) (37 * menuDensity);
            int margin = (int) (16 * density);
            int spacing = (int) (10 * menuDensity);
            int cardPadding = (int) (14 * menuDensity);
            int paddingH = (int) (20 * menuDensity);

            GradientDrawable blackCircle = new GradientDrawable();
            blackCircle.setShape(GradientDrawable.OVAL);
            blackCircle.setColor(Color.parseColor("#1E1E1E"));

            GradientDrawable controlCircle = new GradientDrawable();
            controlCircle.setShape(GradientDrawable.OVAL);
            controlCircle.setColor(Color.parseColor("#2E2E2E"));

            GradientDrawable redCircle = new GradientDrawable();
            redCircle.setShape(GradientDrawable.OVAL);
            redCircle.setColor(Color.parseColor("#E53935"));

            GradientDrawable cardBg = new GradientDrawable();
            cardBg.setShape(GradientDrawable.RECTANGLE);
            cardBg.setColor(Color.parseColor("#F01A1A1A"));
            cardBg.setCornerRadius(18 * menuDensity);
            cardBg.setStroke((int) (1 * menuDensity), Color.parseColor("#33FFFFFF"));

            // --- 1. FULLSCREEN BACKDROP SCRIM (OUTSIDE CLICK DISMISS) ---
            scrimView = new View(activity);
            scrimView.setLayoutParams(new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 
                    ViewGroup.LayoutParams.MATCH_PARENT));
            scrimView.setBackgroundColor(Color.parseColor("#4D000000")); // 30% black
            scrimView.setVisibility(View.GONE);
            scrimView.setOnClickListener(v -> hideMenu());

            // --- 2. UNIFIED MENU CARD ---
            menuCard = new LinearLayout(activity);
            menuCard.setOrientation(LinearLayout.VERTICAL);
            menuCard.setBackground(cardBg);
            menuCard.setPadding(cardPadding, cardPadding, cardPadding, cardPadding);
            FrameLayout.LayoutParams cardParams = new FrameLayout.LayoutParams(
                    (int) (320 * menuDensity), 
                    ViewGroup.LayoutParams.WRAP_CONTENT);
            menuCard.setLayoutParams(cardParams);
            menuCard.setVisibility(View.GONE);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                menuCard.setElevation(12 * menuDensity);
            }

            // Quick Sites Buttons
            LinearLayout.LayoutParams siteBtnParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, (int) (44 * menuDensity));
            siteBtnParams.setMargins(0, 0, 0, spacing);

            for (SiteEntry site : MAIN_SITES) {
                GradientDrawable siteBg = new GradientDrawable();
                siteBg.setShape(GradientDrawable.RECTANGLE);
                siteBg.setColor(Color.parseColor("#2E2E2E"));
                siteBg.setCornerRadius(22 * menuDensity);

                Button siteBtn = new Button(activity);
                siteBtn.setText(site.name);
                siteBtn.setAllCaps(false);
                siteBtn.setTextColor(Color.WHITE);
                siteBtn.setTextSize(15 * MENU_SCALE);
                siteBtn.setBackground(siteBg);
                siteBtn.setPadding(paddingH, 0, paddingH, 0);
                siteBtn.setLayoutParams(siteBtnParams);
                siteBtn.setOnClickListener(v -> navigateToSite(site.url, menuDensity));
                menuCard.addView(siteBtn);
            }

            // Consolidated Extra Apps Menu (Collapsible with Categorized Sub-Menus)
            categoryCollapseCallbacks.clear();
            int totalExtraApps = getTotalExtraAppsCount();
            if (!EXTRA_CATEGORIES.isEmpty()) {
                GradientDrawable extraToggleBg = new GradientDrawable();
                extraToggleBg.setShape(GradientDrawable.RECTANGLE);
                extraToggleBg.setColor(Color.parseColor("#1E2433"));
                extraToggleBg.setCornerRadius(22 * menuDensity);
                extraToggleBg.setStroke((int) (1 * menuDensity), Color.parseColor("#5C7CFA"));

                extraAppsToggleBtn = new Button(activity);
                extraAppsToggleBtn.setText("🗂️  Extra Apps (" + totalExtraApps + ")  ▾");
                extraAppsToggleBtn.setAllCaps(false);
                extraAppsToggleBtn.setTextColor(Color.parseColor("#91A7FF"));
                extraAppsToggleBtn.setTextSize(14 * MENU_SCALE);
                extraAppsToggleBtn.setBackground(extraToggleBg);
                extraAppsToggleBtn.setPadding(paddingH, 0, paddingH, 0);
                extraAppsToggleBtn.setLayoutParams(siteBtnParams);

                extraAppsScrollView = new ScrollView(activity) {
                    @Override
                    protected void onMeasure(int widthMeasureSpec, int heightMeasureSpec) {
                        int maxHeight = (int) (240 * menuDensity);
                        super.onMeasure(widthMeasureSpec, MeasureSpec.makeMeasureSpec(maxHeight, MeasureSpec.AT_MOST));
                    }
                };
                LinearLayout.LayoutParams scrollParams = new LinearLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                scrollParams.setMargins(0, 0, 0, spacing);
                extraAppsScrollView.setLayoutParams(scrollParams);
                extraAppsScrollView.setVisibility(View.GONE);

                LinearLayout categoriesContainer = new LinearLayout(activity);
                categoriesContainer.setOrientation(LinearLayout.VERTICAL);
                categoriesContainer.setLayoutParams(new FrameLayout.LayoutParams(
                        ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

                for (CategoryEntry category : EXTRA_CATEGORIES) {
                    if (category.sites.isEmpty()) continue;

                    GradientDrawable catHeaderBg = new GradientDrawable();
                    catHeaderBg.setShape(GradientDrawable.RECTANGLE);
                    catHeaderBg.setColor(Color.parseColor("#23293A"));
                    catHeaderBg.setCornerRadius(18 * menuDensity);
                    catHeaderBg.setStroke((int) (1 * menuDensity), Color.parseColor("#3B4D7A"));

                    final String collapsedTitle = category.title + " (" + category.sites.size() + ")  ▾";
                    final String expandedTitle = category.title + " (" + category.sites.size() + ")  ▴";

                    final Button catToggleBtn = new Button(activity);
                    catToggleBtn.setText(collapsedTitle);
                    catToggleBtn.setAllCaps(false);
                    catToggleBtn.setTypeface(Typeface.DEFAULT_BOLD);
                    catToggleBtn.setTextColor(Color.parseColor("#B4C6FF"));
                    catToggleBtn.setTextSize(13.5f * MENU_SCALE);
                    catToggleBtn.setBackground(catHeaderBg);
                    catToggleBtn.setPadding(paddingH, 0, paddingH, 0);

                    LinearLayout.LayoutParams catBtnParams = new LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, (int) (40 * menuDensity));
                    catBtnParams.setMargins(0, 0, 0, (int) (6 * menuDensity));
                    catToggleBtn.setLayoutParams(catBtnParams);

                    final LinearLayout catItemsContainer = new LinearLayout(activity);
                    catItemsContainer.setOrientation(LinearLayout.VERTICAL);
                    LinearLayout.LayoutParams catItemsParams = new LinearLayout.LayoutParams(
                            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
                    catItemsParams.setMargins((int) (8 * menuDensity), 0, (int) (8 * menuDensity), (int) (4 * menuDensity));
                    catItemsContainer.setLayoutParams(catItemsParams);
                    catItemsContainer.setVisibility(View.GONE);

                    for (SiteEntry site : category.sites) {
                        GradientDrawable itemBg = new GradientDrawable();
                        itemBg.setShape(GradientDrawable.RECTANGLE);
                        itemBg.setColor(Color.parseColor("#2A2D35"));
                        itemBg.setCornerRadius(16 * menuDensity);

                        Button itemBtn = new Button(activity);
                        itemBtn.setText(site.name);
                        itemBtn.setAllCaps(false);
                        itemBtn.setTextColor(Color.parseColor("#E8E8E8"));
                        itemBtn.setTextSize(13 * MENU_SCALE);
                        itemBtn.setBackground(itemBg);
                        itemBtn.setPadding(paddingH, 0, paddingH, 0);

                        LinearLayout.LayoutParams itemParams = new LinearLayout.LayoutParams(
                                ViewGroup.LayoutParams.MATCH_PARENT, (int) (36 * menuDensity));
                        itemParams.setMargins(0, 0, 0, (int) (6 * menuDensity));
                        itemBtn.setLayoutParams(itemParams);

                        itemBtn.setOnClickListener(v -> navigateToSite(site.url, menuDensity));
                        catItemsContainer.addView(itemBtn);
                    }

                    final Runnable collapseThisCategory = () -> {
                        catItemsContainer.setVisibility(View.GONE);
                        catToggleBtn.setText(collapsedTitle);
                    };
                    categoryCollapseCallbacks.add(collapseThisCategory);

                    catToggleBtn.setOnClickListener(v -> {
                        if (catItemsContainer.getVisibility() == View.VISIBLE) {
                            collapseThisCategory.run();
                        } else {
                            for (Runnable collapse : categoryCollapseCallbacks) {
                                collapse.run();
                            }
                            catItemsContainer.setVisibility(View.VISIBLE);
                            catToggleBtn.setText(expandedTitle);
                            extraAppsScrollView.post(() -> extraAppsScrollView.smoothScrollTo(0, catToggleBtn.getTop()));
                        }
                        menuCard.post(this::repositionMenuCard);
                    });

                    categoriesContainer.addView(catToggleBtn);
                    categoriesContainer.addView(catItemsContainer);
                }

                extraAppsScrollView.addView(categoriesContainer);

                extraAppsToggleBtn.setOnClickListener(v -> {
                    if (extraAppsScrollView.getVisibility() == View.VISIBLE) {
                        for (Runnable collapse : categoryCollapseCallbacks) {
                            collapse.run();
                        }
                        extraAppsScrollView.setVisibility(View.GONE);
                        extraAppsToggleBtn.setText("🗂️  Extra Apps (" + totalExtraApps + ")  ▾");
                    } else {
                        extraAppsScrollView.setVisibility(View.VISIBLE);
                        extraAppsToggleBtn.setText("🗂️  Extra Apps (" + totalExtraApps + ")  ▴");
                    }
                    menuCard.post(this::repositionMenuCard);
                });

                menuCard.addView(extraAppsToggleBtn);
                menuCard.addView(extraAppsScrollView);
            }

            // Controls Row (Back, Zoom -, Zoom +, Refresh, Desktop/Mobile UA, Rotate, Close)
            LinearLayout controlsRow = new LinearLayout(activity);
            controlsRow.setOrientation(LinearLayout.HORIZONTAL);
            controlsRow.setGravity(Gravity.CENTER_VERTICAL);
            LinearLayout.LayoutParams rowParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.WRAP_CONTENT, 
                    ViewGroup.LayoutParams.WRAP_CONTENT);
            rowParams.gravity = Gravity.CENTER_HORIZONTAL;
            controlsRow.setLayoutParams(rowParams);

            LinearLayout.LayoutParams ctrlParams = new LinearLayout.LayoutParams(controlBtnSize, controlBtnSize);
            ctrlParams.setMargins(0, 0, (int) (5 * menuDensity), 0);

            LinearLayout.LayoutParams lastCtrlParams = new LinearLayout.LayoutParams(controlBtnSize, controlBtnSize);
            lastCtrlParams.setMargins(0, 0, 0, 0);

            GradientDrawable backCircle = new GradientDrawable();
            backCircle.setShape(GradientDrawable.OVAL);
            backCircle.setColor(Color.parseColor("#2E2E2E"));

            backButton = new Button(activity);
            backButton.setText("⬅");
            backButton.setTextColor(Color.WHITE);
            backButton.setTextSize(16 * MENU_SCALE);
            backButton.setPadding(0, 0, 0, 0);
            backButton.setBackground(backCircle);
            backButton.setLayoutParams(ctrlParams);
            backButton.setContentDescription("Go Back");
            updateBackButtonState();

            Button zoomOutButton = new Button(activity);
            zoomOutButton.setText("－");
            zoomOutButton.setTextColor(Color.WHITE);
            zoomOutButton.setTextSize(16 * MENU_SCALE);
            zoomOutButton.setPadding(0, 0, 0, 0);
            zoomOutButton.setBackground(controlCircle);
            zoomOutButton.setLayoutParams(ctrlParams);

            GradientDrawable zoomInCircle = new GradientDrawable();
            zoomInCircle.setShape(GradientDrawable.OVAL);
            zoomInCircle.setColor(Color.parseColor("#2E2E2E"));

            Button zoomInButton = new Button(activity);
            zoomInButton.setText("＋");
            zoomInButton.setTextColor(Color.WHITE);
            zoomInButton.setTextSize(16 * MENU_SCALE);
            zoomInButton.setPadding(0, 0, 0, 0);
            zoomInButton.setBackground(zoomInCircle);
            zoomInButton.setLayoutParams(ctrlParams);

            GradientDrawable refreshCircle = new GradientDrawable();
            refreshCircle.setShape(GradientDrawable.OVAL);
            refreshCircle.setColor(Color.parseColor("#2E2E2E"));

            Button refreshButton = new Button(activity);
            refreshButton.setText("↺");
            refreshButton.setTextColor(Color.WHITE);
            refreshButton.setTextSize(18 * MENU_SCALE);
            refreshButton.setPadding(0, 0, 0, 0);
            refreshButton.setBackground(refreshCircle);
            refreshButton.setLayoutParams(ctrlParams);
            refreshButton.setContentDescription("Refresh Page");

            desktopModeCircle = new GradientDrawable();
            desktopModeCircle.setShape(GradientDrawable.OVAL);

            desktopModeButton = new Button(activity);
            desktopModeButton.setTextSize(15 * MENU_SCALE);
            desktopModeButton.setPadding(0, 0, 0, 0);
            desktopModeButton.setBackground(desktopModeCircle);
            desktopModeButton.setLayoutParams(ctrlParams);
            desktopModeButton.setContentDescription("Toggle Desktop/Mobile User-Agent");
            updateDesktopButtonStyle(menuDensity);

            GradientDrawable rotateCircle = new GradientDrawable();
            rotateCircle.setShape(GradientDrawable.OVAL);
            rotateCircle.setColor(Color.parseColor("#2E2E2E"));

            Button rotateButton = new Button(activity);
            rotateButton.setText("90°");
            rotateButton.setTypeface(Typeface.DEFAULT_BOLD);
            rotateButton.setTextColor(Color.WHITE);
            rotateButton.setTextSize(13 * MENU_SCALE);
            rotateButton.setPadding(0, 0, 0, 0);
            rotateButton.setBackground(rotateCircle);
            rotateButton.setLayoutParams(ctrlParams);
            rotateButton.setContentDescription("Rotate Screen");

            GradientDrawable closeCircle = new GradientDrawable();
            closeCircle.setShape(GradientDrawable.OVAL);
            closeCircle.setColor(Color.parseColor("#2E2E2E"));

            Button closeMenuButton = new Button(activity);
            closeMenuButton.setText("⬇");
            closeMenuButton.setTextColor(Color.WHITE);
            closeMenuButton.setTextSize(16 * MENU_SCALE);
            closeMenuButton.setPadding(0, 0, 0, 0);
            closeMenuButton.setBackground(closeCircle);
            closeMenuButton.setLayoutParams(lastCtrlParams);
            closeMenuButton.setContentDescription("Close Menu");

            controlsRow.addView(backButton);
            controlsRow.addView(zoomOutButton);
            controlsRow.addView(zoomInButton);
            controlsRow.addView(refreshButton);
            controlsRow.addView(desktopModeButton);
            controlsRow.addView(rotateButton);
            controlsRow.addView(closeMenuButton);

            // --- SLIDE TO EXIT BAR ---
            FrameLayout slideTrack = new FrameLayout(activity);
            LinearLayout.LayoutParams trackParams = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, (int) (46 * menuDensity));
            trackParams.setMargins(0, (int) (14 * menuDensity), 0, 0);
            slideTrack.setLayoutParams(trackParams);

            GradientDrawable trackBg = new GradientDrawable();
            trackBg.setShape(GradientDrawable.RECTANGLE);
            trackBg.setColor(Color.parseColor("#252525"));
            trackBg.setCornerRadius(23 * menuDensity);
            trackBg.setStroke((int) (1 * menuDensity), Color.parseColor("#33FFFFFF"));
            slideTrack.setBackground(trackBg);

            slideLabel = new TextView(activity);
            slideLabel.setText("Slide to Exit ❯❯❯");
            slideLabel.setTextColor(Color.parseColor("#99FFFFFF"));
            slideLabel.setTextSize(14 * MENU_SCALE);
            slideLabel.setGravity(Gravity.CENTER);
            FrameLayout.LayoutParams labelParams = new FrameLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT);
            slideLabel.setLayoutParams(labelParams);
            slideTrack.addView(slideLabel);

            int thumbSize = (int) (38 * menuDensity);
            int thumbMargin = (int) (4 * menuDensity);
            slideThumb = new TextView(activity);
            slideThumb.setText("✕");
            slideThumb.setTextColor(Color.WHITE);
            slideThumb.setTextSize(16 * MENU_SCALE);
            slideThumb.setGravity(Gravity.CENTER);

            GradientDrawable thumbBg = new GradientDrawable();
            thumbBg.setShape(GradientDrawable.OVAL);
            thumbBg.setColor(Color.parseColor("#E53935"));
            slideThumb.setBackground(thumbBg);

            FrameLayout.LayoutParams thumbParams = new FrameLayout.LayoutParams(thumbSize, thumbSize);
            thumbParams.gravity = Gravity.START | Gravity.CENTER_VERTICAL;
            thumbParams.setMargins(thumbMargin, 0, 0, 0);
            slideThumb.setLayoutParams(thumbParams);
            slideTrack.addView(slideThumb);

            slideThumb.setOnTouchListener(new View.OnTouchListener() {
                private float downRawX;
                private float startX;
                private boolean exitTriggered = false;

                private void triggerExit(View thumbView, float maxX) {
                    if (exitTriggered) return;
                    exitTriggered = true;
                    thumbView.animate().cancel();
                    thumbView.setX(maxX);
                    slideThumb.setText("✓");
                    trackBg.setColor(Color.parseColor("#C62828"));
                    trackBg.setStroke((int) (1.5f * menuDensity), Color.parseColor("#FF8A80"));
                    if (slideLabel != null) {
                        slideLabel.animate().cancel();
                        slideLabel.setText("Closing...");
                        slideLabel.setTypeface(Typeface.DEFAULT_BOLD);
                        slideLabel.setTextColor(Color.WHITE);
                        slideLabel.setAlpha(1.0f);
                    }
                    if (scrimView != null) {
                        scrimView.setOnClickListener(null);
                        scrimView.setBackgroundColor(Color.parseColor("#E6000000"));
                    }
                    if (webView != null) {
                        webView.stopLoading();
                        webView.onPause();
                    }
                    // Allow one UI frame for the "Closing..." state to render before teardown
                    thumbView.postDelayed(GodotWebView.this::terminateBoardAndActivity, 60);
                }

                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    if (exitTriggered) return true;
                    float minX = thumbMargin;
                    float maxX = slideTrack.getWidth() - v.getWidth() - thumbMargin;

                    switch (event.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            downRawX = event.getRawX();
                            startX = v.getX();
                            if (v.getParent() != null) {
                                v.getParent().requestDisallowInterceptTouchEvent(true);
                            }
                            return true;

                        case MotionEvent.ACTION_MOVE:
                            float deltaX = event.getRawX() - downRawX;
                            float newX = Math.max(minX, Math.min(startX + deltaX, maxX));
                            v.setX(newX);
                            float progress = (maxX > minX) ? (newX - minX) / (maxX - minX) : 0f;
                            if (progress >= 0.985f) {
                                triggerExit(v, maxX);
                                return true;
                            }
                            if (slideLabel != null) {
                                slideLabel.setAlpha(Math.max(0f, 1.0f - progress * 1.15f));
                            }
                            return true;

                        case MotionEvent.ACTION_UP:
                        case MotionEvent.ACTION_CANCEL:
                            float releaseProgress = (maxX > minX) ? (v.getX() - minX) / (maxX - minX) : 0f;
                            if (releaseProgress >= 0.95f) {
                                triggerExit(v, maxX);
                            } else {
                                v.animate().x(minX).setDuration(200).start();
                                if (slideLabel != null) {
                                    slideLabel.animate().alpha(1.0f).setDuration(200).start();
                                }
                            }
                            return true;
                    }
                    return false;
                }
            });

            slideTrack.setVisibility(View.GONE);

            menuCard.addView(controlsRow);
            menuCard.addView(slideTrack);

            // --- 3. SINGLE DRAGGABLE FLOATING ACTION BUTTON ---
            floatingButton = new Button(activity);
            floatingButton.setText("☰");
            floatingButton.setTextColor(Color.WHITE);
            floatingButton.setTextSize(24);
            floatingButton.setBackground(blackCircle);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                floatingButton.setElevation(8 * density);
            }

            FrameLayout.LayoutParams fabParams = new FrameLayout.LayoutParams(buttonSize, buttonSize);
            floatingButton.setLayoutParams(fabParams);

            // Auto-fade runnable
            idleFadeRunnable = () -> {
                if (floatingButton != null && !isMenuOpen) {
                    floatingButton.animate().alpha(0.175f).setDuration(500).start();
                }
            };

            // Touch Listener: Drag vs Tap with screen clamping
            int touchSlop = ViewConfiguration.get(activity).getScaledTouchSlop();
            floatingButton.setOnTouchListener(new View.OnTouchListener() {
                private float dX, dY;
                private float downRawX, downRawY;
                private boolean isDragging = false;

                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    switch (event.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            downRawX = event.getRawX();
                            downRawY = event.getRawY();
                            dX = v.getX() - downRawX;
                            dY = v.getY() - downRawY;
                            isDragging = false;
                            resetIdleFade(true);
                            return true;

                        case MotionEvent.ACTION_MOVE:
                            float deltaX = event.getRawX() - downRawX;
                            float deltaY = event.getRawY() - downRawY;
                            if (!isDragging && Math.hypot(deltaX, deltaY) > touchSlop) {
                                isDragging = true;
                            }
                            if (isDragging && layout != null) {
                                float newX = event.getRawX() + dX;
                                float newY = event.getRawY() + dY;
                                float maxX = layout.getWidth() - v.getWidth() - margin;
                                float maxY = layout.getHeight() - v.getHeight() - margin;
                                newX = Math.max(margin, Math.min(newX, maxX));
                                newY = Math.max(margin, Math.min(newY, maxY));
                                v.setX(newX);
                                v.setY(newY);
                            }
                            return true;

                        case MotionEvent.ACTION_UP:
                            if (!isDragging) {
                                showMenu();
                            } else {
                                scheduleIdleFade();
                            }
                            return true;

                        case MotionEvent.ACTION_CANCEL:
                            scheduleIdleFade();
                            return true;
                    }
                    return false;
                }
            });

            // --- CLICK LISTENERS ---
            closeMenuButton.setOnClickListener(v -> hideMenu());

            backButton.setOnClickListener(v -> {
                if (customView != null) {
                    exitCustomFullscreen();
                    hideMenu();
                } else if (webView != null && webView.canGoBack()) {
                    webView.goBack();
                    hideMenu();
                }
            });

            refreshButton.setOnClickListener(v -> {
                hideMenu();
                if (webView != null) {
                    webView.reload();
                }
            });

            desktopModeButton.setOnTouchListener(new View.OnTouchListener() {
                private boolean longPressTriggered = false;
                private final Runnable longPressRunnable = () -> {
                    longPressTriggered = true;
                    desktopModeButton.setAlpha(1.0f);
                    defaultDesktopMode = !defaultDesktopMode;
                    activity.getSharedPreferences(PREFS_NAME, Activity.MODE_PRIVATE)
                            .edit()
                            .putBoolean(PREF_DEFAULT_DESKTOP_MODE, defaultDesktopMode)
                            .apply();
                    isDesktopMode = defaultDesktopMode;
                    hideMenu();
                    applyUserAgent(true, menuDensity);
                    showDefaultUaAckDialog(activity, defaultDesktopMode, menuDensity);
                };

                @Override
                public boolean onTouch(View v, MotionEvent event) {
                    switch (event.getActionMasked()) {
                        case MotionEvent.ACTION_DOWN:
                            longPressTriggered = false;
                            v.setAlpha(0.7f);
                            idleHandler.postDelayed(longPressRunnable, 3000);
                            return true;

                        case MotionEvent.ACTION_MOVE:
                            float mx = event.getX();
                            float my = event.getY();
                            if (mx < 0 || mx > v.getWidth() || my < 0 || my > v.getHeight()) {
                                idleHandler.removeCallbacks(longPressRunnable);
                                v.setAlpha(1.0f);
                            }
                            return true;

                        case MotionEvent.ACTION_UP:
                            idleHandler.removeCallbacks(longPressRunnable);
                            v.setAlpha(1.0f);
                            if (!longPressTriggered) {
                                float ux = event.getX();
                                float uy = event.getY();
                                if (ux >= 0 && ux <= v.getWidth() && uy >= 0 && uy <= v.getHeight()) {
                                    isDesktopMode = !isDesktopMode;
                                    hideMenu();
                                    applyUserAgent(true, menuDensity);
                                }
                            }
                            return true;

                        case MotionEvent.ACTION_CANCEL:
                            idleHandler.removeCallbacks(longPressRunnable);
                            v.setAlpha(1.0f);
                            return true;
                    }
                    return false;
                }
            });

            zoomInButton.setOnClickListener(v -> {
                if (currentZoomIndex < zoomLevels.length - 1) {
                    currentZoomIndex++;
                    applyCurrentZoom();
                }
            });

            zoomOutButton.setOnClickListener(v -> {
                if (currentZoomIndex > 0) {
                    currentZoomIndex--;
                    applyCurrentZoom();
                }
            });

            Runnable postRotateRefresh = () -> webView.postDelayed(() -> {
                webView.requestLayout();
                webView.invalidate();
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                    webView.evaluateJavascript("window.dispatchEvent(new Event('resize'));", null);
                }
                if (floatingButton != null && layout != null) {
                    float targetX = layout.getWidth() - buttonSize - margin;
                    float targetY = layout.getHeight() - buttonSize - margin;
                    floatingButton.setX(targetX);
                    floatingButton.setY(targetY);
                }
            }, 350);

            rotateButton.setOnClickListener(v -> {
                if (currentOrientationIndex == -1) {
                    int currentOrientation = activity.getResources().getConfiguration().orientation;
                    currentOrientationIndex = (currentOrientation == Configuration.ORIENTATION_PORTRAIT) ? 1 : 0;
                }
                currentOrientationIndex = (currentOrientationIndex + 1) % ORIENTATION_CYCLE.length;
                activity.setRequestedOrientation(ORIENTATION_CYCLE[currentOrientationIndex]);

                hideMenu();
                postRotateRefresh.run();
            });

            rotateButton.setOnLongClickListener(v -> {
                currentOrientationIndex = 0;
                activity.setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE);

                hideMenu();
                postRotateRefresh.run();
                return true;
            });

            // Re-pin floating button whenever layout dimensions / orientation change
            layout.addOnLayoutChangeListener((v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
                int w = right - left;
                int h = bottom - top;
                int oldW = oldRight - oldLeft;
                int oldH = oldBottom - oldTop;
                if (w > 0 && h > 0 && (w != oldW || h != oldH)) {
                    if (floatingButton != null) {
                        float targetX = w - buttonSize - margin;
                        float targetY = h - buttonSize - margin;
                        floatingButton.setX(targetX);
                        floatingButton.setY(targetY);
                    }
                    if (isMenuOpen) {
                        hideMenu();
                    }
                }
            });

            // --- ADD VIEWS IN Z-ORDER ---
            floatingButton.setVisibility(View.GONE);
            layout.addView(scrimView);
            layout.addView(menuCard);
            layout.addView(floatingButton);

            webView.loadUrl(url);
        });
    }

    private void repositionMenuCard() {
        if (menuCard == null || layout == null) return;
        float density = layout.getResources().getDisplayMetrics().density;
        int margin = (int) (16 * density);

        menuCard.measure(
                View.MeasureSpec.makeMeasureSpec(layout.getWidth(), View.MeasureSpec.AT_MOST),
                View.MeasureSpec.makeMeasureSpec(layout.getHeight(), View.MeasureSpec.AT_MOST)
        );
        int menuWidth = menuCard.getMeasuredWidth();
        int menuHeight = menuCard.getMeasuredHeight();

        float targetX = (layout.getWidth() - menuWidth) / 2f;
        float targetY = (layout.getHeight() - menuHeight) / 2f;

        targetX = Math.max(margin, Math.min(targetX, layout.getWidth() - menuWidth - margin));
        targetY = Math.max(margin, Math.min(targetY, layout.getHeight() - menuHeight - margin));

        menuCard.setX(targetX);
        menuCard.setY(targetY);
    }

    private void showMenu() {
        if (menuCard == null || layout == null) return;
        isMenuOpen = true;
        resetIdleFade(true);
        updateBackButtonState();
        if (floatingButton != null) {
            floatingButton.setVisibility(View.GONE);
        }
        scrimView.setVisibility(View.VISIBLE);
        menuCard.setVisibility(View.VISIBLE);

        float density = layout.getResources().getDisplayMetrics().density;
        if (slideThumb != null) {
            slideThumb.setX(4 * density * MENU_SCALE);
        }
        if (slideLabel != null) {
            slideLabel.setAlpha(1.0f);
        }

        repositionMenuCard();
    }

    private void hideMenu() {
        if (!isMenuOpen) return;
        isMenuOpen = false;
        if (menuCard != null) menuCard.setVisibility(View.GONE);
        if (scrimView != null) scrimView.setVisibility(View.GONE);
        for (Runnable collapse : categoryCollapseCallbacks) {
            collapse.run();
        }
        if (extraAppsScrollView != null) extraAppsScrollView.setVisibility(View.GONE);
        if (extraAppsToggleBtn != null) extraAppsToggleBtn.setText("🗂️  Extra Apps (" + getTotalExtraAppsCount() + ")  ▾");
        if (floatingButton != null) {
            floatingButton.setVisibility(View.GONE);
        }
    }

    private void scheduleIdleFade() {
        if (idleHandler != null && idleFadeRunnable != null) {
            idleHandler.removeCallbacks(idleFadeRunnable);
            idleHandler.postDelayed(idleFadeRunnable, 4000);
        }
    }

    private void resetIdleFade(boolean makeOpaque) {
        if (idleHandler != null && idleFadeRunnable != null) {
            idleHandler.removeCallbacks(idleFadeRunnable);
        }
        if (makeOpaque && floatingButton != null) {
            floatingButton.animate().alpha(1.0f).setDuration(150).start();
        }
    }

    private void updateBackButtonState() {
        if (backButton == null) return;
        boolean canBack = (customView != null) || (webView != null && webView.canGoBack());
        backButton.setAlpha(canBack ? 1.0f : 0.35f);
        backButton.setEnabled(canBack);
    }

    private void updateDesktopButtonStyle(float density) {
        if (desktopModeButton == null || desktopModeCircle == null) return;
        if (isDesktopMode) {
            desktopModeButton.setText("🖥");
            desktopModeButton.setTextColor(Color.parseColor("#91A7FF"));
            desktopModeCircle.setColor(Color.parseColor("#1E2433"));
            desktopModeCircle.setStroke((int) (1.5f * density), Color.parseColor("#5C7CFA"));
        } else {
            desktopModeButton.setText("📱");
            desktopModeButton.setTextColor(Color.WHITE);
            desktopModeCircle.setColor(Color.parseColor("#2E2E2E"));
            desktopModeCircle.setStroke(0, Color.TRANSPARENT);
        }
    }

    private void showDefaultUaAckDialog(Activity activity, boolean isDesktopDefault, float menuDensity) {
        if (activity == null || activity.isFinishing()) return;

        LinearLayout dialogCard = new LinearLayout(activity);
        dialogCard.setOrientation(LinearLayout.VERTICAL);
        dialogCard.setGravity(Gravity.CENTER_HORIZONTAL);
        int pad = (int) (24 * menuDensity);
        dialogCard.setPadding(pad, pad, pad, pad);

        GradientDrawable cardBg = new GradientDrawable();
        cardBg.setShape(GradientDrawable.RECTANGLE);
        cardBg.setColor(Color.parseColor("#1A1A1A"));
        cardBg.setCornerRadius(16 * menuDensity);
        cardBg.setStroke((int) (1.5f * menuDensity), Color.parseColor("#33FFFFFF"));
        dialogCard.setBackground(cardBg);

        TextView titleView = new TextView(activity);
        titleView.setText("Default User-Agent Saved");
        titleView.setTextColor(Color.WHITE);
        titleView.setTextSize(16 * MENU_SCALE);
        titleView.setTypeface(Typeface.DEFAULT_BOLD);
        titleView.setGravity(Gravity.CENTER);
        dialogCard.addView(titleView);

        TextView msgView = new TextView(activity);
        msgView.setText(isDesktopDefault
                ? "🖥  Desktop Mode is now the default for all sites."
                : "📱  Mobile Mode is now the default for all sites.");
        msgView.setTextColor(Color.parseColor("#D9FFFFFF"));
        msgView.setTextSize(13 * MENU_SCALE);
        msgView.setGravity(Gravity.CENTER);
        LinearLayout.LayoutParams msgParams = new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        msgParams.setMargins(0, (int) (12 * menuDensity), 0, (int) (20 * menuDensity));
        msgView.setLayoutParams(msgParams);
        dialogCard.addView(msgView);

        Button okBtn = new Button(activity);
        okBtn.setText("OK");
        okBtn.setAllCaps(false);
        okBtn.setTextColor(Color.WHITE);
        okBtn.setTextSize(14 * MENU_SCALE);
        okBtn.setTypeface(Typeface.DEFAULT_BOLD);

        GradientDrawable okBg = new GradientDrawable();
        okBg.setShape(GradientDrawable.RECTANGLE);
        okBg.setColor(Color.parseColor("#5C7CFA"));
        okBg.setCornerRadius(10 * menuDensity);
        okBtn.setBackground(okBg);

        LinearLayout.LayoutParams okParams = new LinearLayout.LayoutParams(
                (int) (140 * menuDensity), (int) (42 * menuDensity));
        okBtn.setLayoutParams(okParams);
        dialogCard.addView(okBtn);

        AlertDialog dialog = new AlertDialog.Builder(activity)
                .setView(dialogCard)
                .setCancelable(true)
                .create();

        okBtn.setOnClickListener(v -> dialog.dismiss());

        dialog.show();
        if (dialog.getWindow() != null) {
            dialog.getWindow().setBackgroundDrawable(new ColorDrawable(Color.TRANSPARENT));
            dialog.getWindow().setLayout((int) (320 * menuDensity), ViewGroup.LayoutParams.WRAP_CONTENT);
        }
    }

    private void navigateToSite(String url, float density) {
        exitCustomFullscreen();
        if (isDesktopMode != defaultDesktopMode) {
            isDesktopMode = defaultDesktopMode;
            applyUserAgent(false, density);
        }
        if (webView != null) {
            String targetUrl = url;
            if (targetUrl.contains("youtube.com")) {
                if (isDesktopMode && !targetUrl.contains("app=desktop")) {
                    targetUrl += (targetUrl.contains("?") ? "&" : "?") + "app=desktop";
                } else if (!isDesktopMode && !targetUrl.contains("app=mobile")) {
                    targetUrl += (targetUrl.contains("?") ? "&" : "?") + "app=mobile";
                }
            }
            webView.loadUrl(targetUrl);
        }
        hideMenu();
    }

    private void applyUserAgent(boolean reloadPage, float density) {
        if (webView == null) return;
        WebSettings settings = webView.getSettings();
        if (isDesktopMode) {
            settings.setUserAgentString(DESKTOP_USER_AGENT);
        } else if (defaultUserAgent != null) {
            settings.setUserAgentString(defaultUserAgent);
        }
        updateDesktopButtonStyle(density);

        if (reloadPage) {
            String currentUrl = webView.getUrl();
            if (currentUrl != null) {
                if (isDesktopMode && currentUrl.contains("youtube.com")) {
                    String desktopUrl = currentUrl.replace("://m.youtube.com", "://www.youtube.com")
                            .replace("?app=mobile", "")
                            .replace("&app=mobile", "");
                    if (!desktopUrl.contains("app=desktop")) {
                        desktopUrl += (desktopUrl.contains("?") ? "&" : "?") + "app=desktop";
                    }
                    webView.loadUrl(desktopUrl);
                    return;
                } else if (!isDesktopMode && currentUrl.contains("youtube.com")) {
                    String mobileUrl = currentUrl.replace("://www.youtube.com", "://m.youtube.com")
                            .replace("?app=desktop", "")
                            .replace("&app=desktop", "");
                    if (!mobileUrl.contains("app=mobile")) {
                        mobileUrl += (mobileUrl.contains("?") ? "&" : "?") + "app=mobile";
                    }
                    webView.loadUrl(mobileUrl);
                    return;
                }
            }
            webView.reload();
        }
    }

    private void exitCustomFullscreen() {
        if (customView != null) {
            if (layout != null) {
                layout.removeView(customView);
            }
            customView = null;
        }
        if (webView != null) {
            webView.setVisibility(View.VISIBLE);
        }
        if (customViewCallback != null) {
            customViewCallback.onCustomViewHidden();
            customViewCallback = null;
        }
    }

    private void applyCurrentZoom() {
        if (webView != null) {
            int zoomPercent = zoomLevels[currentZoomIndex];
            webView.getSettings().setTextZoom(zoomPercent);
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
                String js = "document.documentElement.style.zoom = '" + zoomPercent + "%';";
                webView.evaluateJavascript(js, null);
            }
        }
    }

    @UsedByGodot
    public void close() {
        runOnUiThread(() -> {
            resetIdleFade(false);
            exitCustomFullscreen();
            if (layout != null) {
                layout.removeAllViews();
                ViewGroup parent = (ViewGroup) layout.getParent();
                if (parent != null) {
                    parent.removeView(layout);
                }
                layout = null;
                webView = null;
                scrimView = null;
                menuCard = null;
                floatingButton = null;
                slideThumb = null;
                slideLabel = null;
                extraAppsToggleBtn = null;
                extraAppsScrollView = null;
                categoryCollapseCallbacks.clear();
                backButton = null;
                desktopModeButton = null;
                desktopModeCircle = null;
                isDesktopMode = false;
                isMenuOpen = false;
                currentZoomIndex = 1;
            }
        });
    }
}