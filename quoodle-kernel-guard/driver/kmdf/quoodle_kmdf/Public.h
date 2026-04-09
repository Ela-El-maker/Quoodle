/*++

Module Name:

    public.h

Abstract:

    This module contains the common declarations shared by driver
    and user applications.

Environment:

    user and kernel

--*/

//
// Define an Interface Guid so that app can find the device and talk to it.
//

DEFINE_GUID (GUID_DEVINTERFACE_quoodlekmdf,
    0x4631d794,0x3c91,0x4198,0x80,0x03,0xd5,0xa7,0x6b,0x74,0x4e,0x8b);
// {4631d794-3c91-4198-8003-d5a76b744e8b}
