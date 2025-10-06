package org.eaglcoin

import akka.actor.ActorSystem
import akka.http.scaladsl.Http
import akka.http.scaladsl.server.Directives._
import com.typesafe.config.ConfigFactory

object EaglApp {
  def main(args: Array[String]): Unit = {
    println("=== EAGL Node ===")

    // Load your config
    val conf = ConfigFactory.load()
    val nodeName = conf.getString("eagl.nodeName")
    val bindAddress = conf.getString("eagl.bindAddress")
    val restBind = conf.getString("restApi.bindAddress")
    val restPort = conf.getInt("restApi.port")

    println(s"Node Name: $nodeName")
    println(s"Bind Address: $bindAddress")

    implicit val system: ActorSystem = ActorSystem("eagl-node")

    // --- REST routes ---
    val routes =
      path("info") {
        get {
          complete(s"""
            {
              "name": "$nodeName",
              "bindAddress": "$bindAddress",
              "restApi": "$restBind:$restPort",
              "status": "running"
            }
          """)
        }
      }

    // Start REST API server
    Http().newServerAt(restBind, restPort).bind(routes)

    println(s"REST API bound to $restBind:$restPort")
    println("EAGL Node initialized successfully.")
  }
}
