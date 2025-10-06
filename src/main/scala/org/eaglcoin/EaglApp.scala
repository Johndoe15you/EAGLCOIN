package org.eaglcoin

import akka.actor.ActorSystem
import org.ergoplatform.nodeView.ErgoNodeViewRef
import org.ergoplatform.nodeView.wallet.WalletService
import org.ergoplatform.http.api.{ApiRoutes, ErgoApiModule}
import org.ergoplatform.settings.ErgoSettings

object EaglApp {
  def main(args: Array[String]): Unit = {
    println("=== EAGL Node ===")

    // Load settings (reads your application.conf)
    val settings = ErgoSettings.read(args)

    println(s"Loading config from: ${settings.scorexSettings.configPath}")
    println(s"Node Name: ${settings.scorexSettings.network.nodeName}")
    println(s"Bind Address: ${settings.scorexSettings.network.bindAddress}")

    implicit val system: ActorSystem = ActorSystem("eagl-node")

    // Start node core (ledger + networking)
    val nodeViewRef = ErgoNodeViewRef(settings)(system)

    // Start wallet service (required by REST API)
    val walletService = WalletService(settings)(system)

    // ✅ Start REST API
    val apiModule = new ErgoApiModule(settings, nodeViewRef, walletService)
    ApiRoutes.startRestApi(apiModule, settings.scorexSettings.restApi)(system)

    println(s"REST API bound to ${settings.scorexSettings.restApi.bindAddress}:${settings.scorexSettings.restApi.port}")
    println("EAGL Node initialized successfully.")
  }
}
