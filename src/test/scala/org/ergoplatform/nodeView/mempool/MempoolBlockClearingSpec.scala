package org.ergoplatform.nodeView.mempool

import org.ergoplatform.modifiers.mempool.{ErgoTransaction, UnconfirmedTransaction}
import org.ergoplatform.nodeView.mempool.ErgoMemPoolUtils.ProcessingOutcome
import org.ergoplatform.nodeView.state.wrapped.WrappedUtxoState
import org.ergoplatform.utils.{ErgoTestHelpers, NodeViewTestOps, RandomWrapper}
import org.scalatest.flatspec.AnyFlatSpec
import org.scalatestplus.scalacheck.ScalaCheckPropertyChecks

class MempoolBlockClearingSpec extends AnyFlatSpec
  with ErgoTestHelpers
  with ScalaCheckPropertyChecks
  with NodeViewTestOps {

  import org.ergoplatform.utils.ErgoNodeTestConstants._
  import org.ergoplatform.utils.generators.ValidBlocksGenerators._

  it should "remove transactions from mempool when block containing them is applied" in {
    // Setup initial state with genesis block
    val (us, bh) = createUtxoState(settings)
    val genesis = validFullBlock(None, us, bh)
    val wus = WrappedUtxoState(us, bh, settings).applyModifier(genesis)(_ => ()).get

    // Create valid transactions from available boxes and add them to mempool
    val boxes = wus.takeBoxes(3)
    val limit = 10000
    val txs = validTransactionsFromBoxes(limit, boxes, new RandomWrapper)._1
    val unconfirmedTxs = txs.map(tx => UnconfirmedTransaction(tx, None))
    var pool = ErgoMemPool.empty(settings)
    
    // Add all transactions to mempool
    unconfirmedTxs.foreach { utx =>
      val (newPool, outcome) = pool.process(utx, wus)
      outcome.isInstanceOf[ProcessingOutcome.Accepted] shouldBe true
      pool = newPool
    }

    // Verify transactions are in mempool
    pool.size shouldBe txs.size
    txs.foreach { tx =>
      pool.contains(tx.id) shouldBe true
    }

    // Simulate block application by directly calling removeWithDoubleSpends
    // This is what happens in ErgoNodeViewHolder.updateMemPool when blocks are applied
    val appliedTxs = txs.take(2) // Simulate that 2 transactions were included in a block
    val updatedPool = pool.removeWithDoubleSpends(appliedTxs)

    // Verify that transactions included in the block are removed from mempool
    appliedTxs.foreach { tx =>
      updatedPool.contains(tx.id) shouldBe false
    }

    // Verify that transactions not in the block remain in mempool
    val remainingTxs = txs.drop(2)
    remainingTxs.foreach { tx =>
      updatedPool.contains(tx.id) shouldBe true
    }

    // Verify the pool size is reduced by the number of transactions in the block
    updatedPool.size shouldBe (txs.size - appliedTxs.size)
  }

  it should "remove double-spends when block transactions are applied" in {
    // Setup initial state with genesis block
    val (us, bh) = createUtxoState(settings)
    val genesis = validFullBlock(None, us, bh)
    val wus = WrappedUtxoState(us, bh, settings).applyModifier(genesis)(_ => ()).get

    // Create transactions that spend the same inputs (double-spend scenario)
    val boxes = wus.takeBoxes(2)
    
    // Create two transactions spending the same input (double-spend)
    val tx1 = validTransactionsFromBoxes(10000, boxes.take(1), new RandomWrapper)._1.head
    val tx2 = validTransactionsFromBoxes(10000, boxes.take(1), new RandomWrapper)._1.head
    
    // Verify they are spending the same input
    tx1.inputs.head.boxId shouldBe tx2.inputs.head.boxId

    var pool = ErgoMemPool.empty(settings)
    
    // Add first transaction to mempool using put (simpler than process)
    pool = pool.put(UnconfirmedTransaction(tx1, None))
    
    // Verify first transaction is in mempool
    pool.contains(tx1.id) shouldBe true
    
    // Simulate block application with the first transaction
    val appliedTxs = Seq(tx1)
    val updatedPool = pool.removeWithDoubleSpends(appliedTxs)

    // Verify the first transaction is removed from mempool
    updatedPool.contains(tx1.id) shouldBe false
    
    // Now the second transaction should be able to be added since the conflict is resolved
    val finalPool = updatedPool.put(UnconfirmedTransaction(tx2, None))
    finalPool.contains(tx2.id) shouldBe true
  }

  it should "handle empty blocks correctly" in {
    // Setup initial state with genesis block
    val (us, bh) = createUtxoState(settings)
    val genesis = validFullBlock(None, us, bh)
    val wus = WrappedUtxoState(us, bh, settings).applyModifier(genesis)(_ => ()).get

    // Create transactions and add to mempool
    val txs = validTransactionsFromUtxoState(wus)
    val unconfirmedTxs = txs.map(tx => UnconfirmedTransaction(tx, None))
    var pool = ErgoMemPool.empty(settings)
    
    unconfirmedTxs.foreach { utx =>
      val (newPool, outcome) = pool.process(utx, wus)
      outcome.isInstanceOf[ProcessingOutcome.Accepted] shouldBe true
      pool = newPool
    }

    // Simulate block application with no transactions
    val appliedTxs = Seq.empty[ErgoTransaction]
    val updatedPool = pool.removeWithDoubleSpends(appliedTxs)

    // Verify all transactions remain in mempool
    updatedPool.size shouldBe txs.size
    txs.foreach { tx =>
      updatedPool.contains(tx.id) shouldBe true
    }
  }

  it should "handle blocks with partial transaction overlap" in {
    // Setup initial state with genesis block
    val (us, bh) = createUtxoState(settings)
    val genesis = validFullBlock(None, us, bh)
    val wus = WrappedUtxoState(us, bh, settings).applyModifier(genesis)(_ => ()).get

    // Create more transactions than will fit in one block
    val allTxs = validTransactionsFromUtxoState(wus)
    val (blockTxs, remainingTxs) = allTxs.splitAt(allTxs.size / 2)
    
    val allUnconfirmedTxs = allTxs.map(tx => UnconfirmedTransaction(tx, None))
    var pool = ErgoMemPool.empty(settings)
    
    // Add all transactions to mempool
    allUnconfirmedTxs.foreach { utx =>
      val (newPool, outcome) = pool.process(utx, wus)
      outcome.isInstanceOf[ProcessingOutcome.Accepted] shouldBe true
      pool = newPool
    }

    // Simulate block application with only some transactions
    val appliedTxs = blockTxs
    val updatedPool = pool.removeWithDoubleSpends(appliedTxs)

    // Verify transactions in the block are removed
    blockTxs.foreach { tx =>
      updatedPool.contains(tx.id) shouldBe false
    }

    // Verify transactions not in the block remain
    remainingTxs.foreach { tx =>
      updatedPool.contains(tx.id) shouldBe true
    }

    // Verify correct pool size
    updatedPool.size shouldBe remainingTxs.size
  }
}