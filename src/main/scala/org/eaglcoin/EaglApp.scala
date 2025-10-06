package org.eaglcoin

import org.eaglcoin.settings.EaglSettingsReader

object EaglApp {
  def main(args: Array[String]): Unit = {
    println("=== EAGL Node ===")
    val configPath = if (args.nonEmpty) args(0) else "src/main/resources/application.conf"
    println(s"Loading config from: $configPath")

    val settings = EaglSettingsReader.read(configPath)

    println(s"Node Name: ${settings.nodeName}")
    println(s"Bind Address: ${settings.bindAddress}")

    // Placeholder for starting networking, blockchain, etc.
    println("EAGL Node initialized successfully.")
  }
}
