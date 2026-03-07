#include <WebView2EnvironmentOptions.h>
#include <wil/wrl.h>

#include "../utils/log.h"
#include "../utils/native_log.h"
#include "webview_environment.h"

#include "webview_environment_manager.h"

namespace flutter_inappwebview_plugin
{
  using namespace Microsoft::WRL;

  WebViewEnvironment::WebViewEnvironment(const FlutterInappwebviewWindowsPlugin* plugin, const std::string& id)
    : plugin(plugin), id(id),
    channelDelegate(std::make_unique<WebViewEnvironmentChannelDelegate>(this, plugin->registrar->messenger()))
  {}

  void WebViewEnvironment::create(const std::unique_ptr<WebViewEnvironmentSettings> settings, const std::function<void(HRESULT)> completionHandler)
  {
    NativeLog("WebViewEnvironment::create start");
    if (!plugin) {
      NativeLog("WebViewEnvironment::create plugin=null");
      if (completionHandler) {
        completionHandler(E_FAIL);
      }
      return;
    }

    auto hwnd = plugin->webViewEnvironmentManager->getHWND();
    if (!hwnd) {
      NativeLog("WebViewEnvironment::create hwnd=null");
      if (completionHandler) {
        completionHandler(E_FAIL);
      }
      return;
    }
    NativeLog("WebViewEnvironment::create hwnd ok");

    auto options = Make<CoreWebView2EnvironmentOptions>();
    if (settings) {
      if (settings->additionalBrowserArguments.has_value()) {
        options->put_AdditionalBrowserArguments(utf8_to_wide(settings->additionalBrowserArguments.value()).c_str());
      }
      if (settings->allowSingleSignOnUsingOSPrimaryAccount.has_value()) {
        options->put_AllowSingleSignOnUsingOSPrimaryAccount(settings->allowSingleSignOnUsingOSPrimaryAccount.value());
      }
      if (settings->language.has_value()) {
        options->put_Language(utf8_to_wide(settings->language.value()).c_str());
      }
      if (settings->targetCompatibleBrowserVersion.has_value()) {
        options->put_TargetCompatibleBrowserVersion(utf8_to_wide(settings->targetCompatibleBrowserVersion.value()).c_str());
      }
      wil::com_ptr<ICoreWebView2EnvironmentOptions4> options4;
      if (succeededOrLog(options->QueryInterface(IID_PPV_ARGS(&options4))) && settings->customSchemeRegistrations.has_value()) {
        std::vector<ICoreWebView2CustomSchemeRegistration*> registrations = {};
        for (auto& customSchemeRegistration : settings->customSchemeRegistrations.value()) {
          registrations.push_back(std::move(customSchemeRegistration->toWebView2CustomSchemeRegistration()));
        }
        options4->SetCustomSchemeRegistrations(static_cast<UINT32>(registrations.size()), registrations.data());
      }
    }

    NativeLog("CreateCoreWebView2EnvironmentWithOptions call");
    auto hr = CreateCoreWebView2EnvironmentWithOptions(
      settings && settings->browserExecutableFolder.has_value() ? utf8_to_wide(settings->browserExecutableFolder.value()).c_str() : nullptr,
      settings && settings->userDataFolder.has_value() ? utf8_to_wide(settings->userDataFolder.value()).c_str() : nullptr,
      options.Get(),
      Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
        [this, hwnd, completionHandler](HRESULT result, wil::com_ptr<ICoreWebView2Environment> environment) -> HRESULT
        {
          NativeLog(std::string("WebViewEnvironment env callback result=") + std::to_string(result) +
            (environment ? " env=ok" : " env=null"));
          if (succeededOrLog(result)) {
            environment_ = std::move(environment);

            auto hr = environment_->CreateCoreWebView2Controller(hwnd, Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
              [this, completionHandler](HRESULT result, wil::com_ptr<ICoreWebView2Controller> controller) -> HRESULT
              {
                NativeLog(std::string("WebViewEnvironment controller callback result=") + std::to_string(result) +
                  (controller ? " controller=ok" : " controller=null"));
                if (succeededOrLog(result)) {
                  webViewController_ = std::move(controller);
                  const auto webview_hr = webViewController_->get_CoreWebView2(&webView_);
                  NativeLog(std::string("get_CoreWebView2 hr=") + std::to_string(webview_hr) +
                    (webView_ ? " webView=ok" : " webView=null"));
                  if (FAILED(webview_hr) || !webView_) {
                    if (completionHandler) {
                      completionHandler(webview_hr);
                    }
                    return S_OK;
                  }
                  webViewController_->put_IsVisible(false);
                }
                if (completionHandler) {
                  completionHandler(result);
                }
                return S_OK;
              }).Get());

            NativeLog(std::string("CreateCoreWebView2Controller returned hr=") + std::to_string(hr));
            if (failedAndLog(hr) && completionHandler) {
              completionHandler(hr);
            }
          }
          else if (completionHandler) {
            completionHandler(result);
          }
          return S_OK;
        }).Get());

    NativeLog(std::string("CreateCoreWebView2EnvironmentWithOptions returned hr=") + std::to_string(hr));
    if (failedAndLog(hr) && completionHandler) {
      completionHandler(hr);
    }
  }

  WebViewEnvironment::~WebViewEnvironment()
  {
    debugLog("dealloc WebViewEnvironment");
  }
}
