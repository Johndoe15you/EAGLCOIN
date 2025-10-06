package org.eaglcoin.settings

import com.typesafe.config.{Config, ConfigFactory}

case class EaglSettings(nodeName: String, bindAddress: String)

object EaglSettingsReader {
  def read(configPath: String): EaglSettings = {
    val config: Config = ConfigFactory.parseFile(new java.io.File(configPath)).resolve()
    val eaglConfig = config.getConfig("eagl")

    val nodeName = eaglConfig.getString("nodeName")
    val bindAddress = eaglConfig.getString("bindAddress")

    EaglSettings(nodeName, bindAddress)
  }
}
