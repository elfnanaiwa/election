#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>
#include <string>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  // Build the assets path relative to the executable directory
  wchar_t module_path[MAX_PATH];
  GetModuleFileName(nullptr, module_path, MAX_PATH);
  std::wstring exe_dir(module_path);
  size_t last_slash = exe_dir.find_last_of(L"\\/");
  if (last_slash != std::wstring::npos) {
    exe_dir = exe_dir.substr(0, last_slash);
  }
  std::wstring assets_path = exe_dir + L"\\data";
  flutter::DartProject project(assets_path);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"", origin, size)) {
    return EXIT_FAILURE;
  }
  // Remove window icons to hide default Flutter branding.
  HWND hwnd = window.GetHandle();
  if (hwnd) {
    SendMessage(hwnd, WM_SETICON, ICON_SMALL, 0);
    SendMessage(hwnd, WM_SETICON, ICON_BIG, 0);
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
