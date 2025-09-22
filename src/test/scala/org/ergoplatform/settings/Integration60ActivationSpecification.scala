package org.ergoplatform.settings

import org.ergoplatform.nodeView.state.{ErgoStateContext, VotingData}
import org.ergoplatform.utils.ErgoCorePropertyTest
import org.ergoplatform.settings.Parameters.NoParameter

class Integration60ActivationSpecification extends ErgoCorePropertyTest {
  import org.ergoplatform.utils.ErgoCoreTestConstants._
  import org.ergoplatform.utils.generators.ErgoCoreGenerators._

  private val votingEpochLength = 2
  private val softForkEpochs = 2
  private val activationEpochs = 3
  private val activationHeight = 100

  implicit val votingSettings: VotingSettings =
    VotingSettings(
      votingEpochLength,
      softForkEpochs = softForkEpochs,
      activationEpochs = activationEpochs,
      version2ActivationHeight = activationHeight,
      version2ActivationDifficultyHex = "01"
    )

  private val updSettings = chainSettings.copy(voting = votingSettings)

  property("Full activation scenario with parameter validation") {
    var esc = new ErgoStateContext(Seq(), None, genesisStateDigest, parameters, validationSettingsNoIl, VotingData.empty)(updSettings)
    val voteFor60 = 120: Byte

    // Phase 1: Voting period (blocks before activation)
    (1 until activationHeight).foreach { height =>
      val votes = if (height % votingEpochLength == 1) Array(voteFor60, NoParameter, NoParameter) else Array(NoParameter, NoParameter, NoParameter)
      val header = defaultHeaderGen.sample.get.copy(height = height, votes = votes, version = 3: Byte)
      esc = esc. appendHeader(header).toOption.get
    }

    // Verify rules before activation
    esc.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe true

    // unknown considered active as they may come from clients of future versions
    esc.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true

    // Phase 2: Activation block
    val activationHeader = defaultHeaderGen.sample.get.copy(height = activationHeight, version = 4: Byte)
    esc = esc.appendHeader(activationHeader).toOption.get

    // Verify rules after activation
    esc.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe false
    esc.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true

    // Phase 3: Post-activation with new parameters
    (activationHeight + 1 to activationHeight + 10).foreach { height =>
      val header = defaultHeaderGen.sample.get.copy(height = height, version = 4: Byte)
      esc = esc.appendHeader(header).toOption.get
      
      // Verify that rule 414 is still active after processing more blocks
      esc.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true
      esc.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe false
    }
  }

  property("Mixed network compatibility test") {
    // Simulate older client (v3) and newer client (v4) interacting
    var escV3 = new ErgoStateContext(Seq(), None, genesisStateDigest, parameters, validationSettingsNoIl, VotingData.empty)(updSettings)
    var escV4 = new ErgoStateContext(Seq(), None, genesisStateDigest, parameters, validationSettingsNoIl, VotingData.empty)(updSettings)

    // Both clients process same blocks until activation
    (1 until activationHeight).foreach { height =>
      val header = defaultHeaderGen.sample.get.copy(height = height, version = 3: Byte)
      escV3 = escV3.appendHeader(header).toOption.get
      escV4 = escV4.appendHeader(header).toOption.get
    }

    // At activation, V4 client upgrades
    val activationHeader = defaultHeaderGen.sample.get.copy(height = activationHeight, version = 4: Byte)
    escV4 = escV4.appendHeader(activationHeader).toOption.get

    // V3 client continues with version 3
    val v3Header = defaultHeaderGen.sample.get.copy(height = activationHeight, version = 3: Byte)
    escV3 = escV3.appendHeader(v3Header).toOption.get

    // V4 client should have disabled rule 409 and enabled rule 414
    escV4.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe false
    escV4.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true

    // V3 client should keep original rules
    escV3.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe true
    escV3.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true

    // Both should be able to process the same chain despite different rule sets
    (activationHeight + 1 to activationHeight + 5).foreach { height =>
      val header = defaultHeaderGen.sample.get.copy(height = height, version = 4: Byte)
      
      // V4 client accepts version 4 blocks
      escV4 = escV4.appendHeader(header).toOption.get
      
      // V3 client should reject version 4 blocks (incompatible)
      val v3Result = escV3.appendHeader(header)
      v3Result.isFailure shouldBe true
    }
  }

  property("Parameter validation edge cases") {
    // Test various parameter scenarios that should work with rule 414
    val testCases = Seq(
      // Same parameters
      Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000),
      // Additional parameters in received block
      Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000, Parameters.SubblocksPerBlockIncrease -> 2),
      // Multiple additional parameters
      Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000, Parameters.SubblocksPerBlockIncrease -> 2, 200.toByte -> 123, 201.toByte -> 456)
    )

    testCases.foreach { receivedParams =>
      val localParams = Parameters(100, Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000), ErgoValidationSettingsUpdate.empty)
      val blockParams = Parameters(100, receivedParams, ErgoValidationSettingsUpdate.empty)

      // Should validate successfully with matchParameters60
      Parameters.matchParameters60(localParams, blockParams, 4).isSuccess shouldBe true

      // But should fail with original matchParameters for cases with additional parameters
      if (receivedParams.size > localParams.parametersTable.size) {
        Parameters.matchParameters(localParams, blockParams).isFailure shouldBe true
      }
    }

    // Test cases that should fail even with relaxed rules
    val failingCases = Seq(
      // Different values for same parameter
      Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 2000000),
      // Different height
      (Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000), 101),
      // Missing required parameters
      Map(Parameters.BlockVersion -> 4)
    )

    failingCases.foreach {
      case tuple: (Map[Byte, Int], Int) @unchecked =>
        val (params, height) = tuple
        val localParams = Parameters(100, Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000), ErgoValidationSettingsUpdate.empty)
        val blockParams = Parameters(height, params, ErgoValidationSettingsUpdate.empty)
        Parameters.matchParameters60(localParams, blockParams, 4).isFailure shouldBe true
      
      case params: Map[Byte, Int] @unchecked =>
        val localParams = Parameters(100, Map(Parameters.BlockVersion -> 4, Parameters.StorageFeeFactorIncrease -> 1000000), ErgoValidationSettingsUpdate.empty)
        val blockParams = Parameters(100, params, ErgoValidationSettingsUpdate.empty)
        Parameters.matchParameters60(localParams, blockParams, 4).isFailure shouldBe true
    }
  }

  property("Backward compatibility during activation period") {
    var esc = new ErgoStateContext(Seq(), None, genesisStateDigest, parameters, validationSettingsNoIl, VotingData.empty)(updSettings)

    // Process blocks with mixed parameters during activation transition
    (activationHeight - 5 to activationHeight + 5).foreach { height =>
      val version = if (height < activationHeight) 3: Byte else 4: Byte
      
      val header = defaultHeaderGen.sample.get.copy(height = height, version = version)
      esc = esc.appendHeader(header).toOption.get
      
      // Verify rule state during transition
      if (height < activationHeight) {
        esc.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe true
        esc.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true
      } else {
        esc.validationSettings.isActive(ValidationRules.exMatchParameters) shouldBe false
        esc.validationSettings.isActive(ValidationRules.exMatchParameters60) shouldBe true
      }
    }
  }
}
