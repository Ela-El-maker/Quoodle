#include <ntddk.h>
#include <ntstrsafe.h>

#include "quoodle_ioctl.h"

static LONG g_exec_counter = 0;

static void FillResponseDefaults(QUOODLE_IOCTL_RESPONSE *resp) {
  RtlZeroMemory(resp, sizeof(*resp));
  resp->version = QUOODLE_IOCTL_VERSION;
  resp->timestamp_unix = (uint64_t)KeQueryInterruptTime() / 10000000ULL;
  resp->status = 1;
  resp->error_code = 9000;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "not_implemented");
  resp->result_length = 0;
  resp->signature_length = 0;
}

static void BuildExecId(char *buffer, size_t buffer_len) {
  LONG id = InterlockedIncrement(&g_exec_counter);
  (void)RtlStringCchPrintfA(buffer, buffer_len, "kexec-%ld", id);
}

static void HandlePing(QUOODLE_IOCTL_REQUEST *req, QUOODLE_IOCTL_RESPONSE *resp) {
  resp->status = 0;
  resp->error_code = 0;
  RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "");
  BuildExecId(resp->kernel_exec_id, sizeof(resp->kernel_exec_id));
  RtlStringCchCopyA(resp->request_id, sizeof(resp->request_id), req->request_id);
  RtlStringCchCopyA(resp->result_json, sizeof(resp->result_json), "{\"status\":\"ok\",\"message\":\"pong\"}");
  resp->result_length = (uint32_t)strlen(resp->result_json);
}

static NTSTATUS DispatchCreateClose(PDEVICE_OBJECT DeviceObject, PIRP Irp) {
  UNREFERENCED_PARAMETER(DeviceObject);
  Irp->IoStatus.Status = STATUS_SUCCESS;
  Irp->IoStatus.Information = 0;
  IoCompleteRequest(Irp, IO_NO_INCREMENT);
  return STATUS_SUCCESS;
}

static NTSTATUS DispatchDeviceControl(PDEVICE_OBJECT DeviceObject, PIRP Irp) {
  UNREFERENCED_PARAMETER(DeviceObject);
  PIO_STACK_LOCATION stack = IoGetCurrentIrpStackLocation(Irp);
  ULONG code = stack->Parameters.DeviceIoControl.IoControlCode;

  if (code != IOCTL_QUOODLE_EXECUTE) {
    Irp->IoStatus.Status = STATUS_INVALID_DEVICE_REQUEST;
    Irp->IoStatus.Information = 0;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return STATUS_INVALID_DEVICE_REQUEST;
  }

  if (stack->Parameters.DeviceIoControl.InputBufferLength < sizeof(QUOODLE_IOCTL_REQUEST) ||
      stack->Parameters.DeviceIoControl.OutputBufferLength < sizeof(QUOODLE_IOCTL_RESPONSE)) {
    Irp->IoStatus.Status = STATUS_BUFFER_TOO_SMALL;
    Irp->IoStatus.Information = 0;
    IoCompleteRequest(Irp, IO_NO_INCREMENT);
    return STATUS_BUFFER_TOO_SMALL;
  }

  QUOODLE_IOCTL_REQUEST *req = (QUOODLE_IOCTL_REQUEST *)Irp->AssociatedIrp.SystemBuffer;
  QUOODLE_IOCTL_RESPONSE *resp = (QUOODLE_IOCTL_RESPONSE *)Irp->AssociatedIrp.SystemBuffer;
  FillResponseDefaults(resp);

  if (req->version != QUOODLE_IOCTL_VERSION) {
    resp->error_code = 4003;
    RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_version");
  } else {
    switch ((QUOODLE_OPCODE)req->opcode) {
      case QOP_EXEC_PING:
        HandlePing(req, resp);
        break;
      default:
        resp->error_code = 4002;
        RtlStringCchCopyA(resp->error_message, sizeof(resp->error_message), "invalid_opcode");
        break;
    }
  }

  Irp->IoStatus.Status = STATUS_SUCCESS;
  Irp->IoStatus.Information = sizeof(QUOODLE_IOCTL_RESPONSE);
  IoCompleteRequest(Irp, IO_NO_INCREMENT);
  return STATUS_SUCCESS;
}

static void DriverUnload(PDRIVER_OBJECT DriverObject) {
  UNICODE_STRING symLink = RTL_CONSTANT_STRING(QUOODLE_DOS_DEVICE_NAME);
  IoDeleteSymbolicLink(&symLink);
  if (DriverObject->DeviceObject) {
    IoDeleteDevice(DriverObject->DeviceObject);
  }
}

NTSTATUS DriverEntry(PDRIVER_OBJECT DriverObject, PUNICODE_STRING RegistryPath) {
  UNREFERENCED_PARAMETER(RegistryPath);

  UNICODE_STRING deviceName = RTL_CONSTANT_STRING(QUOODLE_DEVICE_NAME);
  UNICODE_STRING symLink = RTL_CONSTANT_STRING(QUOODLE_DOS_DEVICE_NAME);
  PDEVICE_OBJECT deviceObject = NULL;

  NTSTATUS status = IoCreateDevice(
      DriverObject,
      0,
      &deviceName,
      FILE_DEVICE_UNKNOWN,
      0,
      FALSE,
      &deviceObject);
  if (!NT_SUCCESS(status)) {
    return status;
  }

  status = IoCreateSymbolicLink(&symLink, &deviceName);
  if (!NT_SUCCESS(status)) {
    IoDeleteDevice(deviceObject);
    return status;
  }

  DriverObject->MajorFunction[IRP_MJ_CREATE] = DispatchCreateClose;
  DriverObject->MajorFunction[IRP_MJ_CLOSE] = DispatchCreateClose;
  DriverObject->MajorFunction[IRP_MJ_DEVICE_CONTROL] = DispatchDeviceControl;
  DriverObject->DriverUnload = DriverUnload;

  return STATUS_SUCCESS;
}
