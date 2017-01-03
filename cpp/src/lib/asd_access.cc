// Copyright (C) 2016 iNuron NV
//
// This file is part of Open vStorage Open Source Edition (OSE),
// as available from
//
//      http://www.openvstorage.org and
//      http://www.openvstorage.com.
//
// This file is free software; you can redistribute it and/or modify it
// under the terms of the GNU Affero General Public License v3 (GNU AGPLv3)
// as published by the Free Software Foundation, in version 3 as it comes in
// the LICENSE.txt file of the Open vStorage OSE distribution.
// Open vStorage is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY of any kind.

// #include "AlbaConfig.h"
// #include "Alba_Connection.h"
// #include "BackendConfig.h"
#include "asd_access.h"
// #include "LocalConfig.h"
// #include "Local_Connection.h"
// #include "S3Config.h"
// #include "S3_Connection.h"

#include "tcp_transport.h"

#include <iostream>

#include <boost/thread/lock_guard.hpp>

namespace alba {

using alba::proxy_protocol::OsdInfo;

#define LOCK() boost::lock_guard<decltype(lock_)> lg__(lock_)

ConnectionPool::ConnectionPool(std::unique_ptr<OsdInfo> config, size_t capacity)
    : config_(std::move(config)), capacity_(capacity) {
  ALBA_LOG(INFO, "Created pool for asd client " << *config_ << ", capacity "
                                                << capacity);
}

ConnectionPool::~ConnectionPool() { clear_(connections_); }

std::shared_ptr<ConnectionPool>
ConnectionPool::create(std::unique_ptr<OsdInfo> config, size_t capacity) {
  return std::make_shared<ConnectionPool>(std::move(config), capacity);
}

std::unique_ptr<Asd_client> ConnectionPool::pop_(Connections &conns) {
  std::unique_ptr<Asd_client> c;
  if (not conns.empty()) {
    c = std::unique_ptr<Asd_client>(&conns.front());
    conns.pop_front();
  }

  return c;
}

void ConnectionPool::clear_(Connections &conns) {
  while (not conns.empty()) {
    pop_(conns);
  }
}

std::unique_ptr<Asd_client> ConnectionPool::make_one_() const {
  throw "TODO should make asd client here";
}

void ConnectionPool::release_connection_(Asd_client *conn) {
  if (conn) {
    LOCK();
    if (connections_.size() < capacity_) {
      connections_.push_front(*conn);
      return;
    }
  }

  delete conn;
}

std::unique_ptr<Asd_client>
ConnectionPool::get_connection(ForceNewConnection force_new) {
  std::unique_ptr<Asd_client> conn;

  if (force_new == ForceNewConnection::F) {
    LOCK();
    auto duration = std::chrono::seconds(5);
    std::unique_ptr<transport::Transport> transport(
        new transport::TCP_transport(config_->ips[0],
                                     std::to_string(config_->port), duration));
    std::unique_ptr<Asd_client> c(new Asd_client(duration, std::move(transport)));
    conn.reset();
  }

  if (not conn) {
    // conn = BackendConnectionInterfacePtr(make_one_().release(), d);
    LOCK();
  }

  // TODO  ASSERT(conn);
  return conn;
}

size_t ConnectionPool::size() const {
  LOCK();
  return connections_.size();
}

size_t ConnectionPool::capacity() const {
  LOCK();
  return capacity_;
}

void ConnectionPool::capacity(size_t cap) {
  Connections tmp;

  {
    LOCK();

    std::swap(capacity_, cap);
    if (connections_.size() > capacity_) {
      for (size_t i = 0; i < capacity_; ++i) {
        Asd_client &c = connections_.front();
        connections_.pop_front();
        tmp.push_front(c);
      }

      std::swap(tmp, connections_);
    }
  }

  clear_(tmp);

  ALBA_LOG(INFO, *config_ << ": updated capacity from " << cap << " to "
                          << capacity());
}
}
