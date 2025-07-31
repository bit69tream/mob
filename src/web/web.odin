package mobWeb

import "core:mem"
import "core:c"
import "base:intrinsics"
import "base:runtime"

import game ".."

@(default_calling_convention = "c")
foreign {
	  calloc  :: proc(num, size: c.size_t) -> rawptr ---
	  free    :: proc(ptr: rawptr) ---
	  malloc  :: proc(size: c.size_t) -> rawptr ---
	  realloc :: proc(ptr: rawptr, size: c.size_t) -> rawptr ---
}

emsAllocator :: proc "contextless" () -> mem.Allocator {
	  return mem.Allocator{emsAllocatorProc, nil}
}

emsAllocatorProc :: proc(
	  allocator_data: rawptr,
	  mode: mem.Allocator_Mode,
	  size, alignment: int,
	  oldMemory: rawptr,
	  oldSize: int,
	  location := #caller_location
) -> (data: []byte, err: mem.Allocator_Error)  {
	  allocAligned :: proc(size, alignment: int, doZero: bool, oldPtr: rawptr = nil) -> ([]byte, mem.Allocator_Error) {
		    a := max(alignment, align_of(rawptr))
		    space := size + a - 1

		    allocated_mem: rawptr
		    if oldPtr != nil {
			      original_old_ptr := mem.ptr_offset((^rawptr)(oldPtr), -1)^
            allocated_mem = realloc(original_old_ptr, c.size_t(space+size_of(rawptr)))
		    } else if doZero {
			      allocated_mem = calloc(c.size_t(space+size_of(rawptr)), 1)
		    } else {
			      allocated_mem = malloc(c.size_t(space+size_of(rawptr)))
		    }
		    alignedMem := rawptr(mem.ptr_offset((^u8)(allocated_mem), size_of(rawptr)))

		    ptr := uintptr(alignedMem)
		    alignedPtr := (ptr - 1 + uintptr(a)) & -uintptr(a)
		    diff := int(alignedPtr - ptr)
		    if (size + diff) > space || allocated_mem == nil {
			      return nil, .Out_Of_Memory
		    }

		    alignedMem = rawptr(alignedPtr)
		    mem.ptr_offset((^rawptr)(alignedMem), -1)^ = allocated_mem

		    return mem.byte_slice(alignedMem, size), nil
	  }

	  freeAligned :: proc(p: rawptr) {
		    if p != nil {
			      free(mem.ptr_offset((^rawptr)(p), -1)^)
		    }
	  }

	  resizeAligned :: proc(p: rawptr, oldSize: int, newSize: int, alignment: int) -> ([]byte, mem.Allocator_Error) {
		    if p == nil {
			      return nil, nil
		    }
		    return allocAligned(newSize, alignment, true, p)
	  }

	  switch mode {
	  case .Alloc:
		    return allocAligned(size, alignment, true)

	  case .Alloc_Non_Zeroed:
		    return allocAligned(size, alignment, false)

	  case .Free:
		    freeAligned(oldMemory)
		    return nil, nil

	  case .Resize:
		    if oldMemory == nil {
			      return allocAligned(size, alignment, true)
		    }

		    bytes := resizeAligned(oldMemory, oldSize, size, alignment) or_return

		    if size > oldSize {
			      new_region := raw_data(bytes[oldSize:])
			      intrinsics.mem_zero(new_region, size - oldSize)
		    }

		    return bytes, nil

	  case .Resize_Non_Zeroed:
		    if oldMemory == nil {
			      return allocAligned(size, alignment, false)
		    }

		    return resizeAligned(oldMemory, oldSize, size, alignment)

	  case .Query_Features:
		    set := (^mem.Allocator_Mode_Set)(oldMemory)
		    if set != nil {
			      set^ = {.Alloc, .Free, .Resize, .Query_Features}
		    }
		    return nil, nil

	  case .Free_All, .Query_Info:
		    return nil, .Mode_Not_Implemented
	  }
	  return nil, .Mode_Not_Implemented
}

ARENA_SIZE :: mem.Megabyte
arenaData := [ARENA_SIZE]byte{}

webContext: runtime.Context

@export
webInit :: proc "c" () {
    context = runtime.default_context()
    context.allocator = emsAllocator()

    tempArena := mem.Arena {}
    mem.arena_init(&tempArena, arenaData[:])
    context.temp_allocator = mem.arena_allocator(&tempArena)

    webContext = context

    game.init()
}

@export
webUpdate :: proc "c" () -> bool {
    context = webContext
    game.update()
    return game.shouldRun
}

@export
webDeinit :: proc "c" () {
    context = webContext
    game.deinit()
}

@export
webWindowSizeChanged :: proc "c" (w, h: c.int) {
    context = webContext
    game.setWindowSize(w, h)
}
