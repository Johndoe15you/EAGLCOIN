package org.ergoplatform.nodeView.wallet

import org.ergoplatform.nodeView.wallet.requests.PaymentRequest
import org.ergoplatform.utils._
import org.ergoplatform.wallet.boxes.BoxSelector.MinBoxValue
import org.scalatest.concurrent.Eventually
import scala.concurrent.duration._

class InputBlockWalletSpec extends ErgoCorePropertyTest with WalletTestOps with Eventually {

  property("locally generated input block transactions prevent double spending") {
    withFixture { implicit w =>
      val addresses = getPublicKeys
      val pubkey = addresses.head.pubkey
      addresses.length should be > 0
      
      // Create initial state with some boxes
      val genesisBlock = makeGenesisBlock(pubkey, randomNewAsset)
      applyBlock(genesisBlock) shouldBe 'success
      
      // Generate a transaction that spends some boxes and creates new ones
      implicit val patienceConfig: PatienceConfig = PatienceConfig(5.second, 300.millis)
      val tx = eventually {
        val sumToSpend = MinBoxValue * 10
        val req = Seq(PaymentRequest(addresses.head, sumToSpend, Array.empty, Map.empty))
        await(wallet.generateTransaction(req)).get
      }
      
      // Scan the transaction as a locally generated input block
      wallet.scanInputBlock(Seq(tx))
      
      // Wait for wallet state to update
      eventually {
        // Verify that we cannot generate another transaction that would double-spend the same inputs
        // This should fail because the inputs are already marked as spent
        val attempt = await(wallet.generateTransaction(Seq(PaymentRequest(addresses.head, MinBoxValue, Array.empty, Map.empty))))
        
        // The generation should fail due to insufficient funds (inputs already spent)
        attempt shouldBe 'failure
      }
    }
  }

  property("remotely generated input block transactions prevent double spending") {
    withFixture { implicit w =>
      val addresses = getPublicKeys
      val pubkey = addresses.head.pubkey
      addresses.length should be > 0
      
      // Create initial state with some boxes
      val genesisBlock = makeGenesisBlock(pubkey, randomNewAsset)
      applyBlock(genesisBlock) shouldBe 'success
      
      // Generate a transaction that spends some boxes and creates new ones
      implicit val patienceConfig: PatienceConfig = PatienceConfig(5.second, 300.millis)
      val tx = eventually {
        val sumToSpend = MinBoxValue * 10
        val req = Seq(PaymentRequest(addresses.head, sumToSpend, Array.empty, Map.empty))
        await(wallet.generateTransaction(req)).get
      }
      
      // Apply the transaction as a remotely generated block (simulating network reception)
      val block = makeNextBlock(getUtxoState, Seq(tx))
      applyBlock(block) shouldBe 'success
      
      // Wait for wallet state to update
      eventually {
        // Verify that we cannot generate another transaction that would double-spend the same inputs
        val attempt = await(wallet.generateTransaction(Seq(PaymentRequest(addresses.head, MinBoxValue, Array.empty, Map.empty))))
        
        // The generation should fail due to insufficient funds (inputs already spent)
        attempt shouldBe 'failure
      }
    }
  }

  property("boxes created in input blocks can be spent in subsequent blocks") {
    withFixture { implicit w =>
      val addresses = getPublicKeys
      val pubkey = addresses.head.pubkey
      addresses.length should be > 0
      
      // Create initial state with some boxes
      val genesisBlock = makeGenesisBlock(pubkey, randomNewAsset)
      applyBlock(genesisBlock) shouldBe 'success
      
      // Generate first transaction that creates outputs
      implicit val patienceConfig: PatienceConfig = PatienceConfig(5.second, 300.millis)
      val tx1 = eventually {
        val sumToSpend = MinBoxValue * 10
        val req = Seq(PaymentRequest(addresses.head, sumToSpend, Array.empty, Map.empty))
        await(wallet.generateTransaction(req)).get
      }
      
      // Apply first transaction as a block (making outputs spendable)
      val block1 = makeNextBlock(getUtxoState, Seq(tx1))
      applyBlock(block1) shouldBe 'success
      
      // Generate second transaction that spends outputs from first transaction
      val tx2 = eventually {
        // Create a transaction spending the outputs from tx1
        val req2 = Seq(PaymentRequest(addresses.head, MinBoxValue, Array.empty, Map.empty))
        await(wallet.generateTransaction(req2)).get
      }
      
      // Verify that tx2 can be created (boxes from tx1 are spendable)
      tx2 should not be null
      tx2.inputs should not be empty
      
      // Apply second transaction as a block
      val block2 = makeNextBlock(getUtxoState, Seq(tx2))
      applyBlock(block2) shouldBe 'success
    }
  }

  property("double spending prevention works for both locally and remotely generated input blocks") {
    withFixture { implicit w =>
      val addresses = getPublicKeys
      val pubkey = addresses.head.pubkey
      addresses.length should be > 0
      
      // Create initial state with some boxes
      val genesisBlock = makeGenesisBlock(pubkey, randomNewAsset)
      applyBlock(genesisBlock) shouldBe 'success
      
      // Generate a transaction
      implicit val patienceConfig: PatienceConfig = PatienceConfig(5.second, 300.millis)
      val tx = eventually {
        val sumToSpend = MinBoxValue * 10
        val req = Seq(PaymentRequest(addresses.head, sumToSpend, Array.empty, Map.empty))
        await(wallet.generateTransaction(req)).get
      }
      
      // Apply as locally generated input block
      wallet.scanInputBlock(Seq(tx))
      
      // Wait for wallet state to update
      Thread.sleep(1000) // Give wallet time to process input block
      eventually {
        // Try to create another transaction that attempts to double-spend the same inputs
        val attempt1 = await(wallet.generateTransaction(Seq(PaymentRequest(addresses.head, MinBoxValue, Array.empty, Map.empty))))
        attempt1 shouldBe 'failure
      }
      
      // Now apply the original transaction as a remote block (simulating network consensus)
      val block = makeNextBlock(getUtxoState, Seq(tx))
      applyBlock(block) shouldBe 'success
      
      // Wait for wallet state to update
      Thread.sleep(1000) // Give wallet time to process on-chain block
      eventually {
        // After the block is applied, the double-spend prevention should still work
        val attempt2 = await(wallet.generateTransaction(Seq(PaymentRequest(addresses.head, MinBoxValue, Array.empty, Map.empty))))
        attempt2 shouldBe 'failure
      }
    }
  }
}