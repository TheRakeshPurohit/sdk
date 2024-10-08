// Copyright (c) 2023, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

#include "vm/ffi/native_assets.h"

#include "vm/hash_table.h"
#include "vm/object_store.h"
#include "vm/symbols.h"

namespace dart {

ArrayPtr GetNativeAssetsMap(Thread* thread) {
  Zone* const zone = thread->zone();
  ObjectStore* const object_store = thread->isolate_group()->object_store();
  auto& native_assets_map =
      Array::Handle(zone, object_store->native_assets_map());
  if (!native_assets_map.IsNull()) {
    return native_assets_map.ptr();
  }

  const auto& native_assets_library =
      Library::Handle(zone, object_store->native_assets_library());
  if (native_assets_library.IsNull()) {
    // Kernel compilation can happen without a native assets library.
    return Array::null();
  }

  auto& pragma = Object::Handle(zone);
  const bool pragma_found = native_assets_library.FindPragma(
      thread, /*only_core=*/false, native_assets_library,
      Symbols::vm_ffi_native_assets(),
      /*multiple=*/false, &pragma);
  ASSERT(pragma_found);

  // This map is formatted as follows:
  //
  // '<target_string>': {
  //   '<asset_uri>': ['<path_type>', '<path (optional)>']
  // }
  //
  // It is generated by: pkg/vm/lib/native_assets/synthesizer.dart
  const auto& abi_map = Map::Cast(pragma);
  const auto& current_abi = String::Handle(
      zone, String::NewFormatted("%s_%s", kTargetOperatingSystemName,
                                 kTargetArchitectureName));
  Map::Iterator abi_iterator(abi_map);
  auto& abi = String::Handle(zone);
  auto& asset_map = Map::Handle(zone);
  while (abi_iterator.MoveNext()) {
    abi = String::RawCast(abi_iterator.CurrentKey());
    if (abi.Equals(current_abi)) {
      asset_map = Map::RawCast(abi_iterator.CurrentValue());
      break;
    }
  }
  const intptr_t asset_map_length = asset_map.IsNull() ? 0 : asset_map.Length();
  NativeAssetsMap map(
      HashTables::New<NativeAssetsMap>(asset_map_length, Heap::kOld));
  if (!asset_map.IsNull()) {
    String& asset = String::Handle(zone);
    Array& path = Array::Handle(zone);
    Map::Iterator iterator2(asset_map);
    bool duplicate_asset = false;
    while (iterator2.MoveNext()) {
      asset = String::RawCast(iterator2.CurrentKey());
      path = Array::RawCast(iterator2.CurrentValue());
      duplicate_asset = map.UpdateOrInsert(asset, path);
      ASSERT(!duplicate_asset);
    }
  }
  native_assets_map = map.Release().ptr();
  object_store->set_native_assets_map(native_assets_map);
  return native_assets_map.ptr();
}

}  // namespace dart
