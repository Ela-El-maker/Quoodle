#include "screenshot_helper.hpp"

#include "../utils/sha256.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cctype>
#include <cstdlib>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <vector>

#ifdef _WIN32
#include <windows.h>
#include <unknwn.h>
#include <objbase.h>
#include <ole2.h>
#include <objidl.h>
#include <propidl.h>
#include <gdiplus.h>
#pragma comment(lib, "gdiplus.lib")
#endif

namespace command
{
namespace
{

struct HelperArgs
{
  std::string output_path;
  std::string meta_path;
  std::string format{"png"};
  std::string resolution{"original"};
  int jpeg_quality{85};
};

bool read_file_binary(const std::string &path, std::string &out)
{
  std::ifstream file(path, std::ios::binary);
  if (!file)
  {
    return false;
  }
  file.seekg(0, std::ios::end);
  const auto len = file.tellg();
  if (len <= 0)
  {
    return false;
  }
  const auto stream_len = static_cast<std::streamsize>(len);
  out.resize(static_cast<size_t>(stream_len));
  file.seekg(0, std::ios::beg);
  file.read(out.data(), stream_len);
  return static_cast<bool>(file);
}

void write_meta_file(const std::string &meta_path, const nlohmann::json &payload)
{
  const std::filesystem::path path(meta_path);
  std::error_code ec;
  std::filesystem::create_directories(path.parent_path(), ec);
  std::ofstream out(meta_path, std::ios::trunc | std::ios::binary);
  if (!out)
  {
    return;
  }
  out << payload.dump(2);
}

bool parse_args(int argc, char **argv, HelperArgs &out)
{
  for (int i = 1; i < argc; ++i)
  {
    const std::string arg = argv[i] ? argv[i] : "";
    if (arg == "--output" && i + 1 < argc)
    {
      out.output_path = argv[++i];
    }
    else if (arg == "--meta" && i + 1 < argc)
    {
      out.meta_path = argv[++i];
    }
    else if (arg == "--format" && i + 1 < argc)
    {
      out.format = argv[++i];
    }
    else if (arg == "--resolution" && i + 1 < argc)
    {
      out.resolution = argv[++i];
    }
    else if (arg == "--quality" && i + 1 < argc)
    {
      out.jpeg_quality = std::max(1, std::min(100, std::atoi(argv[++i])));
    }
  }

  std::transform(out.format.begin(), out.format.end(), out.format.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
  std::transform(out.resolution.begin(), out.resolution.end(), out.resolution.begin(),
                 [](unsigned char c) { return static_cast<char>(std::tolower(c)); });

  if (out.output_path.empty() || out.meta_path.empty())
  {
    return false;
  }
  if (out.format != "png" && out.format != "jpeg")
  {
    out.format = "png";
  }
  if (out.resolution != "original" && out.resolution != "1080p" && out.resolution != "720p")
  {
    out.resolution = "original";
  }
  return true;
}

#ifdef _WIN32
std::wstring utf8_to_wide(const std::string &input)
{
  if (input.empty())
  {
    return {};
  }
  const int size = MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, nullptr, 0);
  if (size <= 1)
  {
    return {};
  }
  std::wstring out(static_cast<size_t>(size - 1), L'\0');
  MultiByteToWideChar(CP_UTF8, 0, input.c_str(), -1, out.data(), size);
  return out;
}

void enable_dpi_awareness_for_capture()
{
  // Prevent DPI virtualization from shrinking the virtual-screen metrics,
  // which can crop captures on scaled displays (for example 150%/200%).
  using SetProcessDpiAwarenessContextFn = BOOL(WINAPI *)(HANDLE);
  if (HMODULE user32 = GetModuleHandleW(L"user32.dll"))
  {
    auto set_context = reinterpret_cast<SetProcessDpiAwarenessContextFn>(
        GetProcAddress(user32, "SetProcessDpiAwarenessContext"));
    if (set_context)
    {
      if (set_context(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2))
      {
        return;
      }
      set_context(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE);
      return;
    }

    using SetProcessDPIAwareFn = BOOL(WINAPI *)(void);
    auto set_legacy = reinterpret_cast<SetProcessDPIAwareFn>(
        GetProcAddress(user32, "SetProcessDPIAware"));
    if (set_legacy)
    {
      set_legacy();
      return;
    }
  }

  HMODULE shcore = LoadLibraryW(L"shcore.dll");
  if (shcore)
  {
    enum PROCESS_DPI_AWARENESS_LOCAL
    {
      PROCESS_DPI_UNAWARE_LOCAL = 0,
      PROCESS_SYSTEM_DPI_AWARE_LOCAL = 1,
      PROCESS_PER_MONITOR_DPI_AWARE_LOCAL = 2
    };
    using SetProcessDpiAwarenessFn = HRESULT(WINAPI *)(PROCESS_DPI_AWARENESS_LOCAL);
    auto set_awareness = reinterpret_cast<SetProcessDpiAwarenessFn>(
        GetProcAddress(shcore, "SetProcessDpiAwareness"));
    if (set_awareness)
    {
      (void)set_awareness(PROCESS_PER_MONITOR_DPI_AWARE_LOCAL);
    }
    FreeLibrary(shcore);
  }
}

bool get_encoder_clsid(const WCHAR *mime, CLSID &clsid)
{
  UINT num = 0;
  UINT bytes = 0;
  if (Gdiplus::GetImageEncodersSize(&num, &bytes) != Gdiplus::Ok || bytes == 0)
  {
    return false;
  }
  std::vector<BYTE> buffer(bytes, 0);
  auto *encoders = reinterpret_cast<Gdiplus::ImageCodecInfo *>(buffer.data());
  if (Gdiplus::GetImageEncoders(num, bytes, encoders) != Gdiplus::Ok)
  {
    return false;
  }
  for (UINT i = 0; i < num; ++i)
  {
    if (encoders[i].MimeType && wcscmp(encoders[i].MimeType, mime) == 0)
    {
      clsid = encoders[i].Clsid;
      return true;
    }
  }
  return false;
}

void compute_target_size(const HelperArgs &args, int src_w, int src_h, int &out_w, int &out_h)
{
  out_w = src_w;
  out_h = src_h;
  if (args.resolution == "original" || src_w <= 0 || src_h <= 0)
  {
    return;
  }

  int target_w = 0;
  int target_h = 0;
  if (args.resolution == "1080p")
  {
    target_w = 1920;
    target_h = 1080;
  }
  else
  {
    target_w = 1280;
    target_h = 720;
  }

  const double sx = static_cast<double>(target_w) / static_cast<double>(src_w);
  const double sy = static_cast<double>(target_h) / static_cast<double>(src_h);
  const double scale = std::min(1.0, std::min(sx, sy));
  out_w = std::max(1, static_cast<int>(src_w * scale));
  out_h = std::max(1, static_cast<int>(src_h * scale));
}

bool capture_bitmap_for_desktop(const HelperArgs &args, HBITMAP &out_bitmap, int &out_width, int &out_height)
{
  out_bitmap = nullptr;
  const int src_x = GetSystemMetrics(SM_XVIRTUALSCREEN);
  const int src_y = GetSystemMetrics(SM_YVIRTUALSCREEN);
  const int src_w = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  const int src_h = GetSystemMetrics(SM_CYVIRTUALSCREEN);
  if (src_w <= 0 || src_h <= 0)
  {
    return false;
  }

  int target_w = src_w;
  int target_h = src_h;
  compute_target_size(args, src_w, src_h, target_w, target_h);
  out_width = target_w;
  out_height = target_h;

  HDC screen_dc = GetDC(nullptr);
  if (!screen_dc)
  {
    return false;
  }
  HDC src_dc = CreateCompatibleDC(screen_dc);
  HDC dst_dc = CreateCompatibleDC(screen_dc);
  if (!src_dc || !dst_dc)
  {
    if (src_dc)
      DeleteDC(src_dc);
    if (dst_dc)
      DeleteDC(dst_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HBITMAP src_bitmap = CreateCompatibleBitmap(screen_dc, src_w, src_h);
  if (!src_bitmap)
  {
    DeleteDC(src_dc);
    DeleteDC(dst_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HGDIOBJ old_src = SelectObject(src_dc, src_bitmap);
  if (!BitBlt(src_dc, 0, 0, src_w, src_h, screen_dc, src_x, src_y, SRCCOPY | CAPTUREBLT))
  {
    SelectObject(src_dc, old_src);
    DeleteObject(src_bitmap);
    DeleteDC(src_dc);
    DeleteDC(dst_dc);
    ReleaseDC(nullptr, screen_dc);
    return false;
  }

  HBITMAP dst_bitmap = nullptr;
  if (target_w == src_w && target_h == src_h)
  {
    dst_bitmap = src_bitmap;
  }
  else
  {
    dst_bitmap = CreateCompatibleBitmap(screen_dc, target_w, target_h);
    if (dst_bitmap)
    {
      HGDIOBJ old_dst = SelectObject(dst_dc, dst_bitmap);
      SetStretchBltMode(dst_dc, HALFTONE);
      SetBrushOrgEx(dst_dc, 0, 0, nullptr);
      StretchBlt(dst_dc, 0, 0, target_w, target_h, src_dc, 0, 0, src_w, src_h, SRCCOPY);
      SelectObject(dst_dc, old_dst);
    }
    DeleteObject(src_bitmap);
  }

  SelectObject(src_dc, old_src);
  DeleteDC(src_dc);
  DeleteDC(dst_dc);
  ReleaseDC(nullptr, screen_dc);

  if (!dst_bitmap)
  {
    return false;
  }
  out_bitmap = dst_bitmap;
  return true;
}

bool save_bitmap_to_file(const HelperArgs &args, HBITMAP bitmap, const std::string &output_path)
{
  const std::wstring wide_path = utf8_to_wide(output_path);
  if (wide_path.empty())
  {
    return false;
  }

  CLSID encoder = {};
  const WCHAR *mime = args.format == "jpeg" ? L"image/jpeg" : L"image/png";
  if (!get_encoder_clsid(mime, encoder))
  {
    return false;
  }

  Gdiplus::Bitmap image(bitmap, nullptr);
  if (args.format == "jpeg")
  {
    Gdiplus::EncoderParameters params{};
    params.Count = 1;
    params.Parameter[0].Guid = Gdiplus::EncoderQuality;
    params.Parameter[0].Type = Gdiplus::EncoderParameterValueTypeLong;
    params.Parameter[0].NumberOfValues = 1;
    ULONG quality = static_cast<ULONG>(std::max(1, std::min(100, args.jpeg_quality)));
    params.Parameter[0].Value = &quality;
    return image.Save(wide_path.c_str(), &encoder, &params) == Gdiplus::Ok;
  }
  return image.Save(wide_path.c_str(), &encoder, nullptr) == Gdiplus::Ok;
}
#endif

int run_helper(const HelperArgs &args)
{
#ifndef _WIN32
  write_meta_file(args.meta_path, {{"status", "error"}, {"reason", "unsupported_platform"}});
  return 2;
#else
  enable_dpi_awareness_for_capture();

  const std::filesystem::path out_path(args.output_path);
  std::error_code ec;
  std::filesystem::create_directories(out_path.parent_path(), ec);

  Gdiplus::GdiplusStartupInput startup_input;
  ULONG_PTR gdiplus_token = 0;
  if (Gdiplus::GdiplusStartup(&gdiplus_token, &startup_input, nullptr) != Gdiplus::Ok)
  {
    write_meta_file(args.meta_path, {{"status", "error"}, {"reason", "gdiplus_startup_failed"}});
    return 3;
  }

  HBITMAP bitmap = nullptr;
  int width = 0;
  int height = 0;
  if (!capture_bitmap_for_desktop(args, bitmap, width, height))
  {
    Gdiplus::GdiplusShutdown(gdiplus_token);
    write_meta_file(args.meta_path, {{"status", "error"}, {"reason", "capture_failed"}});
    return 4;
  }

  const bool saved = save_bitmap_to_file(args, bitmap, args.output_path);
  DeleteObject(bitmap);
  Gdiplus::GdiplusShutdown(gdiplus_token);
  if (!saved)
  {
    write_meta_file(args.meta_path, {{"status", "error"}, {"reason", "save_failed"}});
    return 5;
  }

  std::uint64_t size_bytes = 0;
  std::string checksum;
  const auto file_size = std::filesystem::file_size(out_path, ec);
  if (!ec)
  {
    size_bytes = static_cast<std::uint64_t>(file_size);
  }

  std::string file_bytes;
  if (read_file_binary(args.output_path, file_bytes))
  {
    checksum = sha256_hex(file_bytes);
  }

  write_meta_file(args.meta_path, {
                                     {"status", "ok"},
                                     {"format", args.format},
                                     {"resolution", args.resolution},
                                     {"width", width},
                                     {"height", height},
                                     {"size_bytes", size_bytes},
                                     {"sha256", checksum},
                                     {"output_path", args.output_path},
                                 });
  return 0;
#endif
}

} // namespace

bool IsScreenshotHelperInvocation(int argc, char **argv)
{
  for (int i = 1; i < argc; ++i)
  {
    if (argv[i] && std::string(argv[i]) == "--screenshot-helper")
    {
      return true;
    }
  }
  return false;
}

int TryRunScreenshotHelper(int argc, char **argv)
{
  if (!IsScreenshotHelperInvocation(argc, argv))
  {
    return -1;
  }

  HelperArgs args;
  if (!parse_args(argc, argv, args))
  {
    if (!args.meta_path.empty())
    {
      write_meta_file(args.meta_path, {{"status", "error"}, {"reason", "invalid_args"}});
    }
    return 1;
  }
  return run_helper(args);
}

} // namespace command
