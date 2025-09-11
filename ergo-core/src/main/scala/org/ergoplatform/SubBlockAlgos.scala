package org.ergoplatform

import org.ergoplatform.settings.Parameters

/**
  * Implementation steps:
  * * implement basic input block algorithms (isInput etc)
  * * implement input block network message
  * * implement input block info support in sync tracker
  * * implement downloading input blocks chain
  * * implement avoiding downloading full-blocks
  * * input blocks support in /mining API
  * * sub confirmations API
  */
object SubBlockAlgos {

  // sub blocks per block, adjustable via miners voting
  val subsPerBlock: Int = Parameters.SubsPerBlockDefault

}

