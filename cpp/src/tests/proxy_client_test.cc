/*
Copyright (C) 2016 iNuron NV

This file is part of Open vStorage Open Source Edition (OSE), as available from


    http://www.openvstorage.org and
    http://www.openvstorage.com.

This file is free software; you can redistribute it and/or modify it
under the terms of the GNU Affero General Public License v3 (GNU AGPLv3)
as published by the Free Software Foundation, in version 3 as it comes
in the <LICENSE.txt> file of the Open vStorage OSE distribution.

Open vStorage is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY of any kind.
*/

#include "proxy_client.h"
#include "alba_logger.h"
#include "manifest.h"
#include "gtest/gtest.h"
#include <boost/algorithm/string.hpp>
#include <boost/algorithm/string.hpp>
#include <boost/log/trivial.hpp>

#include "osd_access.h"
#include "osd_info.h"
#include <fstream>
#include <iostream>

using std::string;
using std::cout;
using std::endl;

string env_or_default(const std::string &name, const std::string &def) {
  char *env = getenv(name.c_str());
  if (NULL == env) {
    return def;
  }
  return string(env);
}

auto TIMEOUT = std::chrono::seconds(20);
using alba::proxy_client::Proxy_client;
using alba::proxy_client::make_proxy_client;
using namespace alba;

struct config_exception : std::exception {
  config_exception(string what) : _what(what) {}
  string _what;

  virtual const char *what() const noexcept { return _what.c_str(); }
};

struct config {
  config() {
    PORT = env_or_default("ALBA_PROXY_PORT", "10000");
    HOST = env_or_default("ALBA_PROXY_IP", "127.0.0.1");
    TRANSPORT = alba::transport::Kind::tcp;
    string transport = env_or_default("ALBA_PROXY_TRANSPORT", "tcp");
    boost::algorithm::to_lower(transport);

    if (transport == "rdma") {
      TRANSPORT = alba::transport::Kind::rdma;
    }
    NAMESPACE = "demo";
  }

  string PORT;
  string HOST;
  string NAMESPACE;
  alba::transport::Kind TRANSPORT;
};

TEST(proxy_client, list_objects) {

  ALBA_LOG(WARNING, "starting test:list_objects");
  config cfg;
  cout << "cfg(" << cfg.HOST << ", " << cfg.PORT << ", " << cfg.TRANSPORT << ")"
       << endl;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);
  string ns("demo");
  string first("");

  auto res = client->list_objects(
      ns, first, alba::proxy_client::include_first::T, boost::none,
      alba::proxy_client::include_last::T, -1);

  auto objects = std::get<0>(res);
  auto has_more = std::get<1>(res);
  cout << "received " << objects.size() << " objects" << endl;
  cout << "[ ";
  for (auto &object : objects) {
    cout << object << ",\n";
  }
  cout << " ]" << endl;
  cout << has_more << endl;
  cout << "size ok?" << endl;
  EXPECT_EQ(0, objects.size());
  cout << "has_more ok?" << endl;
  EXPECT_EQ(false, BooleanEnumTrue(has_more));
  cout << "end of test" << endl;
}

TEST(proxy_client, list_namespaces) {

  ALBA_LOG(WARNING, "starting test:list_namespaces");
  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);
  std::string first("");

  auto res = client->list_namespaces(
      first, alba::proxy_client::include_first::T, boost::none,
      alba::proxy_client::include_last::T, -1);

  auto objects = std::get<0>(res);
  alba::proxy_client::has_more has_more = std::get<1>(res);
  cout << "received" << objects.size() << " objects" << endl;
  cout << "[ ";
  for (auto &object : objects) {
    cout << object << ",\n";
  }
  cout << " ]" << endl;
  cout << has_more << endl;
  EXPECT_EQ(1, objects.size());
  EXPECT_EQ(false, BooleanEnumTrue(has_more));
}

TEST(proxy_client, get_object_info) {

  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);

  string name("get_object_info_object");
  string file("./ocaml/alba.native");

  client->write_object_fs(cfg.NAMESPACE, name, file,
                          proxy_client::allow_overwrite::T, nullptr);

  uint64_t size;
  alba::Checksum *checksum;
  std::tie(size, checksum) = client->get_object_info(
      cfg.NAMESPACE, name, proxy_client::consistent_read::T,
      proxy_client::should_cache::T);

  client->write_object_fs(cfg.NAMESPACE, name, file,
                          proxy_client::allow_overwrite::T, checksum);
  delete checksum;
}

TEST(proxy_client, get_proxy_version) {

  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);
  int32_t major;
  int32_t minor;
  int32_t patch;
  std::string hash;

  std::tie(major, minor, patch, hash) = client->get_proxy_version();

  std::cout << "major:" << major << std::endl;
  std::cout << "minor:" << minor << std::endl;
  std::cout << "patch:" << patch << std::endl;
  std::cout << "hash:" << hash << std::endl;
}

double stamp() {
  struct timeval tp;
  gettimeofday(&tp, NULL);
  double t0 = tp.tv_sec + (double)tp.tv_usec / 1e6;
  return t0;
}

TEST(proxy_client, test_ping) {

  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);
  double eps =
      0.1; // otherwise it might fail under valgrind (it was 0.085 once)
  struct timeval timeval0;
  gettimeofday(&timeval0, NULL);
  double t0 = stamp();

  double timestamp = client->ping(1.0);
  double delta = timestamp - t0;
  double t1 = stamp();
  std::cout << "t0:" << t0 << " timestamp:" << timestamp << std::endl;
  std::cout << "delta(t0,timestamp)" << delta << std::endl;
  std::cout << "delta(t1,timestamp)" << t1 - timestamp << std::endl;
  EXPECT_NEAR(delta, 1.0, eps);

  std::cout << "part2" << std::endl;
  t0 = stamp();
  try {
    timestamp = client->ping(25.0);
    // expect failure....
    double t1 = stamp();
    std::cout << "we got here after " << t1 - t0 << " s" << std::endl;
    EXPECT_EQ(true, false);
  } catch (std::exception &e) {
    std::cout << e.what() << std::endl;
    double t1 = stamp();
    delta = t1 - t0;
    std::cout << "t0:" << t0 << " t1:" << t1 << std::endl;
    std::cout << "delta:" << delta << std::endl;
    EXPECT_NEAR(delta, 20.0, eps);
  }
}

TEST(proxy_client, manifest) {
  using namespace proxy_protocol;
  std::ifstream file;
  file.exceptions(std::ifstream::failbit | std::ifstream::badbit);
  file.open("./bin/the_manifest.bin");
  std::stringstream buffer;
  buffer << file.rdbuf();
  std::string data = buffer.str();
  auto size = data.size();
  std::cout << "size:" << size << std::endl;

  ManifestWithNamespaceId mf;
  auto mb = llio::message_buffer::from_string(data);
  llio::message m(mb);
  from(m, mf);

  std::cout << mf << std::endl;
  EXPECT_EQ(mf.name, "with_manifest");
  EXPECT_EQ(mf.max_disks_per_node, 3);
  EXPECT_EQ(mf.namespace_id.i, 5);
}

TEST(proxy_client, test_osd_info) {

  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);

  proxy_protocol::osd_map_t result;

  client->osd_info(result);
  for (auto &p : result) {
    auto osd = p.first;
    auto &ic = *p.second;
    const proxy_protocol::OsdInfo &osd_info = ic.first;
    std::cout << "osd: " << osd << " info: " << osd_info
              << " caps: " << ic.second << std::endl;
  }
}

TEST(proxy_client, test_osd_info2) {
  config cfg;
  using namespace proxy_protocol;
  auto client = make_proxy_client(cfg.HOST, "10000", TIMEOUT, cfg.TRANSPORT);
  osd_maps_t result;
  client->osd_info2(result);
  uint n = 12;
  std::set<alba_id_t> alba_ids;
  for (auto &e : result) {
    const alba_id_t &alba_id = e.first;
    std::cout << "alba_id=" << alba_id << std::endl;
    const auto &infos = e.second;
    alba_ids.insert(alba_id);
    std::map<osd_t, int> osds;
    for (auto &osd_map : infos) {
      auto osd = osd_map.first;

      EXPECT_EQ(osds.find(osd), osds.end());
      osds[osd] = 1;
      auto &pair = *osd_map.second;
      auto &osd_info = pair.first;
      using stuff::operator<<;
      std::cout << "osd=" << osd << ", osd_info=" << osd_info << std::endl;
    }
    EXPECT_EQ(osds.size(), n);
  }
  EXPECT_EQ(result.size(), 2);
  EXPECT_EQ(alba_ids.size(), 2);

  auto &osd_access = alba::proxy_client::OsdAccess::getInstance(5);
  osd_access.update(*client);

  osd_map_t &m = std::get<1>(result[1]);
  for (auto it = m.begin(); it != m.end(); it++) {
    auto osd_id = it->first;
    bool unknown = osd_access.osd_is_unknown(osd_id);
    EXPECT_EQ(unknown, false);
  }
}

void _compare_blocks(std::vector<byte> &block1, byte *block2, uint32_t off,
                     uint32_t len) {
  auto ok = true;
  ALBA_LOG(INFO, "comparing blocks");
  for (uint32_t i = 0; i < len; i++) {
    uint32_t pos = off + i;
    const byte b1 = block1[pos];
    const byte b2 = block2[pos];
    if (b1 != b2) {
      std::cout << "error[" << pos << "]:" << (int)b1 << "!=" << (int)b2
                << std::endl;
      ok = false;
      break;
    }
  }
  EXPECT_TRUE(ok);
}

void _generic_partial_read_test(
    config &cfg, std::string &namespace_, std::string &name,
    std::vector<proxy_protocol::ObjectSlices> &objects_slices,
    std::string &file, bool clear_before_read) {

  boost::optional<alba::proxy_client::RoraConfig> rora_config{100};
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT,
                                  rora_config);
  boost::optional<std::string> preset{"preset_rora"};
  std::ostringstream nos;
  nos << namespace_ << "_" << std::rand();
  string actual_namespace{nos.str()};
  ALBA_LOG(INFO, "creating namespace " << actual_namespace);
  client->create_namespace(actual_namespace, preset);

  // this upload is to 'warm up' the proxy
  // more specifically: the first upload will trigger namespace
  // creation on the fragment cache, and that may cause some fragments
  // of the first chunk to not be successfully stored there, leading
  // to test failure here.
  const auto seq1 = proxy_client::sequences::Sequence().add_upload_fs(
      name + "_dummy", file, nullptr);
  client->apply_sequence(actual_namespace, proxy_client::write_barrier::F,
                         seq1);

  const auto seq2 =
      proxy_client::sequences::Sequence().add_upload_fs(name, file, nullptr);
  ALBA_LOG(INFO, "apply sequence");
  client->apply_sequence(actual_namespace, proxy_client::write_barrier::F,
                         seq2);
  if (clear_before_read) {
    client->invalidate_cache(actual_namespace);
  }
  ALBA_LOG(INFO, "doing partial read");
  alba::statistics::RoraCounter cntr;
  client->read_objects_slices(actual_namespace, objects_slices,
                              proxy_client::consistent_read::F, cntr);

  // verify partially read data
  std::ifstream for_comparison(file, std::ios::binary);
  for (auto &object_slices : objects_slices) {
    for (auto &slice : object_slices.slices) {
      std::vector<byte> bytes2(slice.size);
      for_comparison.seekg(slice.offset);
      for_comparison.read((char *)&bytes2[0], slice.size);
      _compare_blocks(bytes2, slice.buf, 0, slice.size);
    }
  }

  std::cout << "slow_path=" << cntr.slow_path
            << ", fast_path=" << cntr.fast_path << std::endl;
  std::string slow_allowed_s =
      env_or_default("ALBA_TEST_SLOW_ALLOWED", "false");
  bool slow_allowed = "true" == slow_allowed_s;
  if (!slow_allowed) {
    if (clear_before_read) {
      EXPECT_TRUE(cntr.slow_path > 0);
      EXPECT_EQ(cntr.fast_path, 0);
    } else {
      EXPECT_EQ(cntr.slow_path, 0);
      EXPECT_TRUE(cntr.fast_path > 0);
    }
  }
}

TEST(proxy_client, test_partial_read_trivial) {
  std::string namespace_("test_partial_read_trivial");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  uint32_t block_size = 4096;
  std::vector<byte> bytes(block_size);
  SliceDescriptor sd{&bytes[0], 0, block_size};

  std::vector<SliceDescriptor> slices{sd};
  ObjectSlices object_slices{name, slices};
  std::vector<ObjectSlices> objects_slices{object_slices};
  string file("./ocaml/alba.native");
  config cfg;
  _generic_partial_read_test(cfg, namespace_, name, objects_slices, file,
                             false);
}

TEST(proxy_client, test_partial_read_trivial2) {
  std::string namespace_("test_partial_read_trivial2");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  uint32_t block_size = 4096;
  std::vector<byte> bytes(block_size);
  SliceDescriptor sd{&bytes[0], 0, block_size};

  std::vector<SliceDescriptor> slices{sd};
  ObjectSlices object_slices{name, slices};
  std::vector<ObjectSlices> objects_slices{object_slices};
  string file("./ocaml/alba.native");
  config cfg;
  _generic_partial_read_test(cfg, namespace_, name, objects_slices, file, true);
}

TEST(proxy_client, test_partial_read_trivial3) {
  std::string namespace_("test_partial_read_trivial3");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  uint32_t block_size = 4096;
  std::vector<byte> bytes(block_size);
  SliceDescriptor sd{&bytes[0], 0, block_size};

  std::vector<SliceDescriptor> slices{sd};
  ObjectSlices object_slices{name, slices};
  std::vector<ObjectSlices> objects_slices{object_slices};
  string file("./ocaml/src/fragment_cache.ml"); // ~30K => fragments in rocksdb
  config cfg;
  _generic_partial_read_test(cfg, namespace_, name, objects_slices, file,
                             false);
}

TEST(proxy_client, test_partial_read_multislice) {
  std::string namespace_("test_partial_read_multi_slice");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  std::vector<byte> buf(8192);

  SliceDescriptor sd{&buf[0], 0, 4096};

  // slice that spans 2 fragments.
  SliceDescriptor sd2{&buf[4096], (1 << 20) - 10, 4096};

  std::vector<SliceDescriptor> slices{sd, sd2};
  ObjectSlices object_slices{name, slices};
  std::vector<ObjectSlices> objects_slices{object_slices};
  string file("./ocaml/alba.native");
  config cfg;
  _generic_partial_read_test(cfg, namespace_, name, objects_slices, file,
                             false);
}

TEST(proxy_client, test_partial_reads) {
  config cfg;
  std::string namespace_("test_partial_reads");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  std::vector<byte> buf(32768);
  boost::optional<alba::proxy_client::RoraConfig> rora_config{100};
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT,
                                  rora_config);
  boost::optional<std::string> preset{"preset_rora"};
  client->create_namespace(namespace_, preset);
  string file("./ocaml/alba.native");
  client->write_object_fs(namespace_, name, file,
                          proxy_client::allow_overwrite::T, nullptr);
  client->invalidate_cache(namespace_);
  alba::statistics::RoraCounter cntr;
  for (int i = 0; i < 8; i++) {
    SliceDescriptor sd{&buf[0], 0, 4096};
    std::vector<SliceDescriptor> slices{sd};
    ObjectSlices object_slices{name, slices};
    std::vector<ObjectSlices> objects_slices{object_slices};
    client->read_objects_slices(namespace_, objects_slices,
                                proxy_client::consistent_read::F, cntr);
  }
}

TEST(proxy_client, manifest_cache_eviction) {
  config cfg;
  std::string namespace_("manifest_cache_eviction");
  boost::optional<alba::proxy_client::RoraConfig> rora_config{10};
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT,
                                  rora_config);
  boost::optional<std::string> preset{"preset_rora"};
  client->create_namespace(namespace_, preset);
  string file("./ocaml/alba.native");
  for (int i = 0; i < 20; i++) {
    std::ostringstream sos;
    sos << "object_" << i;
    string name = sos.str();
    using namespace proxy_protocol;
    client->write_object_fs(namespace_, name, file,
                            proxy_client::allow_overwrite::T, nullptr);
  }
}

TEST(proxy_client, test_partial_read_fc) {
  std::string namespace_("test_partial_read_fc");
  std::ostringstream sos;
  sos << "with_manifest" << std::rand();
  string name = sos.str();
  using namespace proxy_protocol;
  uint32_t block_size = 4096;
  std::vector<byte> bytes(block_size);
  uint32_t offset = 5 << 20; // chunk 1;
  SliceDescriptor sd{&bytes[0], offset, block_size};

  std::vector<SliceDescriptor> slices{sd};
  ObjectSlices object_slices{name, slices};
  std::vector<ObjectSlices> objects_slices{object_slices};
  string file_name("./ocaml/alba.native");
  config cfg;

  _generic_partial_read_test(cfg, namespace_, name, objects_slices, file_name,
                             false);
}

TEST(proxy_client, apply_sequence) {
  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);

  std::string namespace_("apply_sequence");

  client->create_namespace(namespace_, boost::none);

  auto write_barrier = proxy_client::write_barrier::F;
  std::vector<std::shared_ptr<proxy_client::sequences::Assert>> asserts;
  std::vector<std::shared_ptr<proxy_client::sequences::Update>> updates;

  // empty apply sequence (could be used just for the write barrier)
  client->apply_sequence(namespace_, write_barrier, asserts, updates);

  asserts.push_back(
      std::make_shared<proxy_client::sequences::AssertObjectDoesNotExist>(
          "non existing"));
  auto u1 =
      std::make_shared<proxy_client::sequences::UpdateUploadObjectFromFile>(
          "myobj", "./ocaml/alba.native", nullptr);
  auto u2 =
      std::make_shared<proxy_client::sequences::UpdateDeleteObject>("woosh");
  updates.push_back(u1);
  updates.push_back(u2);
  client->apply_sequence(namespace_, write_barrier, asserts, updates);

  asserts.clear();
  asserts.push_back(
      std::make_shared<proxy_client::sequences::AssertObjectDoesNotExist>(
          "myobj"));
  updates.clear();
  ASSERT_THROW(
      client->apply_sequence(namespace_, write_barrier, asserts, updates),
      alba::proxy_client::proxy_exception);

  asserts.clear();
  updates.clear();
  updates.push_back(
      std::make_shared<proxy_client::sequences::UpdateDeleteObject>("myobj"));
  client->apply_sequence(namespace_, write_barrier, asserts, updates);

  asserts.clear();
  asserts.push_back(
      std::make_shared<proxy_client::sequences::AssertObjectDoesNotExist>(
          "myobj"));
  updates.clear();
  client->apply_sequence(namespace_, write_barrier, asserts, updates);

  const auto seq =
      proxy_client::sequences::Sequence()
          .add_assert("non existing", proxy_client::sequences::ObjectExists::F)
          .add_upload_fs("bar", "./ocaml/alba.native", nullptr);
  client->apply_sequence(namespace_, write_barrier, seq);
}

TEST(proxy_client, manifest_with_ctr) {
  config cfg;
  auto client = make_proxy_client(cfg.HOST, cfg.PORT, TIMEOUT, cfg.TRANSPORT);
  std::string namespace_("manifest_with_ctr");
  boost::optional<std::string> preset("preset_ctr");
  client->create_namespace(namespace_, preset);

  auto write_barrier = proxy_client::write_barrier::F;
  using namespace proxy_client::sequences;
  using namespace std;
  vector<shared_ptr<Assert>> asserts;
  vector<shared_ptr<Update>> updates;

  asserts.push_back(make_shared<AssertObjectDoesNotExist>("not there"));
  auto update = make_shared<UpdateUploadObjectFromFile>(
      "the_object", "./ocaml/alba.native", nullptr);
  updates.push_back(update);
  client->apply_sequence(namespace_, write_barrier, asserts, updates);

  // if we get here, it means we at least could process
  // the response (containing a manifest with AES ctr encryption info)
  // without exception
}
