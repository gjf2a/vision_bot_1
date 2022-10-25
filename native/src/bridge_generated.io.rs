use super::*;
// Section: wire functions

#[no_mangle]
pub extern "C" fn wire_yuv_rgba(
    port_: i64,
    ys: *mut wire_uint_8_list,
    us: *mut wire_uint_8_list,
    vs: *mut wire_uint_8_list,
    width: i64,
    height: i64,
    uv_row_stride: i64,
    uv_pixel_stride: i64,
) {
    wire_yuv_rgba_impl(
        port_,
        ys,
        us,
        vs,
        width,
        height,
        uv_row_stride,
        uv_pixel_stride,
    )
}

#[no_mangle]
pub extern "C" fn wire_get_correlation_flow(
    port_: i64,
    prev_ys: *mut wire_uint_8_list,
    current_ys: *mut wire_uint_8_list,
    width: i64,
    height: i64,
) {
    wire_get_correlation_flow_impl(port_, prev_ys, current_ys, width, height)
}

// Section: allocate functions

#[no_mangle]
pub extern "C" fn new_uint_8_list_0(len: i32) -> *mut wire_uint_8_list {
    let ans = wire_uint_8_list {
        ptr: support::new_leak_vec_ptr(Default::default(), len),
        len,
    };
    support::new_leak_box_ptr(ans)
}

// Section: impl Wire2Api

impl Wire2Api<Vec<u8>> for *mut wire_uint_8_list {
    fn wire2api(self) -> Vec<u8> {
        unsafe {
            let wrap = support::box_from_leak_ptr(self);
            support::vec_from_leak_ptr(wrap.ptr, wrap.len)
        }
    }
}
// Section: wire structs

#[repr(C)]
#[derive(Clone)]
pub struct wire_uint_8_list {
    ptr: *mut u8,
    len: i32,
}

// Section: impl NewWithNullPtr

pub trait NewWithNullPtr {
    fn new_with_null_ptr() -> Self;
}

impl<T> NewWithNullPtr for *mut T {
    fn new_with_null_ptr() -> Self {
        std::ptr::null_mut()
    }
}

// Section: sync execution mode utility

#[no_mangle]
pub extern "C" fn free_WireSyncReturnStruct(val: support::WireSyncReturnStruct) {
    unsafe {
        let _ = support::vec_from_leak_ptr(val.ptr, val.len);
    }
}
