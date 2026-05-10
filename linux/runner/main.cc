#include <webview_cef/webview_cef_plugin.h>
#include "my_application.h"

int main(int argc, char** argv) {
  // CEF (used by webview_cef) spawns child processes with the same binary —
  // initCEFProcesses returns early in those child invocations so they don't
  // also try to run Flutter. Must be the first thing in main.
  initCEFProcesses(argc, argv);
  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
