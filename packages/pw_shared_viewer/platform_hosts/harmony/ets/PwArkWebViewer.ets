import { PwArkWebHost, ENTRY } from './PwArkWebHost';

@Component
export struct PwArkWebViewer {
  host: PwArkWebHost = new PwArkWebHost();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) throw new Error('ArkUI host context unavailable');
    this.host.setAssetReader((path: string) => context.resourceManager.getRawFileContentSync(path));
  }
  aboutToDisappear(): void { this.host.dispose(); }

  build() {
    Web({ src: ENTRY, controller: this.host.controller })
      .javaScriptAccess(true)
      .fileAccess(false)
      .domStorageAccess(false)
      .databaseAccess(false)
      .mixedMode(MixedMode.None)
      .multiWindowAccess(false)
      .javaScriptProxy({ object: this.host, name: 'PWSharedHost',
        methodList: ['postMessage'], controller: this.host.controller })
      .onLoadIntercept((event) => event === undefined ||
        !this.host.allowNavigation(event.data.getRequestUrl(), event.data.isMainFrame()))
      .onInterceptRequest((event) => this.host.intercept(
        event?.request.getRequestUrl() ?? '', event?.request.getRequestMethod() ?? ''))
      .onPageBegin((event) => this.host.pageBegin(event?.url ?? ''))
      .onPageEnd((event) => this.host.pageEnd(event?.url ?? ''))
      .onErrorReceive((event) => {
        if (event?.request.isMainFrame()) this.host.fail('ArkWeb main document load failed');
      })
      .onHttpErrorReceive((event) => {
        if (event?.request.isMainFrame()) this.host.fail('ArkWeb main document HTTP failure');
      })
      .onRenderExited(() => this.host.fail('ArkWeb render process exited'))
      .onVisibleAreaChange([0.0, 1.0], (visible: boolean) => this.host.setForeground(visible))
      .width('100%')
      .height('100%')
  }
}
