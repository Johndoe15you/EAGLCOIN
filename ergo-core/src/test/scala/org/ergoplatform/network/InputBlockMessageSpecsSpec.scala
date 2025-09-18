package org.ergoplatform.network

import org.ergoplatform.mining.InputBlockFields
import org.ergoplatform.modifiers.mempool.ErgoTransaction
import org.ergoplatform.network.message.inputblocks.{
  InputBlockMessageSpec,
  InputBlockTransactionIdsData,
  InputBlockTransactionIdsMessageSpec,
  InputBlockTransactionsData,
  InputBlockTransactionsMessageSpec,
  InputBlockTransactionsRequest,
  InputBlockTransactionsRequestMessageSpec
}
import org.ergoplatform.settings.Constants
import org.ergoplatform.subblocks.InputBlockInfo
import org.ergoplatform.utils.{ErgoCorePropertyTest, SerializationTests}
import org.scalacheck.Gen
import scorex.crypto.authds.merkle.BatchMerkleProof
import scorex.crypto.hash.Blake2b256

class InputBlockMessageSpecsSpec extends ErgoCorePropertyTest with SerializationTests {
  import org.ergoplatform.utils.generators.CoreObjectGenerators._
  import org.ergoplatform.utils.generators.ErgoCoreGenerators._
  import org.ergoplatform.utils.generators.ErgoCoreTransactionGenerators._

  private val inputBlockMessageSpec = InputBlockMessageSpec
  private val inputBlockTransactionIdsMessageSpec = InputBlockTransactionIdsMessageSpec
  private val inputBlockTransactionsMessageSpec = InputBlockTransactionsMessageSpec
  private val inputBlockTransactionsRequestMessageSpec = InputBlockTransactionsRequestMessageSpec

  private def inputBlockInfoGen: Gen[InputBlockInfo] = for {
    header <- defaultHeaderGen
    prevInputBlockId <- Gen.option(genBytes(Constants.ModifierIdSize))
    transactionsDigest <- digest32Gen
    prevTransactionsDigest <- digest32Gen
    weakTxIds <- Gen.option(Gen.listOf(genBytes(ErgoTransaction.WeakIdLength)).map(_.take(5)))
  } yield {
    val merkleProof = BatchMerkleProof(Seq.empty, Seq.empty)(Blake2b256)
    val inputBlockFields = new InputBlockFields(prevInputBlockId, transactionsDigest, prevTransactionsDigest, merkleProof)
    InputBlockInfo(InputBlockInfo.initialMessageVersion, header, inputBlockFields, weakTxIds)
  }

  private def inputBlockTransactionIdsDataGen: Gen[InputBlockTransactionIdsData] = for {
    inputBlockId <- modifierIdGen
    transactionIds <- Gen.listOf(genBytes(ErgoTransaction.WeakIdLength)).map(_.take(5))
  } yield InputBlockTransactionIdsData(inputBlockId, transactionIds)

  private def inputBlockTransactionsDataGen: Gen[InputBlockTransactionsData] = for {
    inputBlockId <- modifierIdGen
    transactions <- Gen.listOf(invalidErgoTransactionGen).map(_.take(3))
  } yield InputBlockTransactionsData(inputBlockId, transactions)

  private def inputBlockTransactionsRequestGen: Gen[InputBlockTransactionsRequest] = for {
    inputBlockId <- modifierIdGen
    txIds <- Gen.listOf(genBytes(ErgoTransaction.WeakIdLength)).map(_.take(5))
  } yield InputBlockTransactionsRequest(inputBlockId, txIds)

  property("InputBlockInfo serialization roundtrip") {
    forAll(inputBlockInfoGen) { info =>
      val bytes = inputBlockMessageSpec.toBytes(info)
      val recovered = inputBlockMessageSpec.parseBytes(bytes)

      recovered.version shouldEqual info.version
      recovered.header shouldEqual info.header
      recovered.prevInputBlockId.map(_.toSeq) shouldEqual info.prevInputBlockId.map(_.toSeq)
      recovered.transactionsDigest.toSeq shouldEqual info.transactionsDigest.toSeq
      recovered.weakTxIds.map(_.map(_.toSeq)) shouldEqual info.weakTxIds.map(_.map(_.toSeq))
    }
  }

  property("InputBlockTransactionIdsData serialization roundtrip") {
    forAll(inputBlockTransactionIdsDataGen) { data =>
      val bytes = inputBlockTransactionIdsMessageSpec.toBytes(data)
      val recovered = inputBlockTransactionIdsMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual data.inputBlockId
      recovered.transactionIds.map(_.toSeq) shouldEqual data.transactionIds.map(_.toSeq)
    }
  }

  property("InputBlockTransactionIdsData serialization with empty transaction ids") {
    forAll(modifierIdGen) { inputBlockId =>
      val emptyData = InputBlockTransactionIdsData(inputBlockId, Seq.empty)
      val bytes = inputBlockTransactionIdsMessageSpec.toBytes(emptyData)
      val recovered = inputBlockTransactionIdsMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual emptyData.inputBlockId
      recovered.transactionIds shouldEqual emptyData.transactionIds
    }
  }

  property("InputBlockTransactionsData serialization roundtrip") {
    forAll(inputBlockTransactionsDataGen) { data =>
      val bytes = inputBlockTransactionsMessageSpec.toBytes(data)
      val recovered = inputBlockTransactionsMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual data.inputBlockId
      recovered.transactions shouldEqual data.transactions
    }
  }

  property("InputBlockTransactionsData serialization with empty transactions") {
    forAll(modifierIdGen) { inputBlockId =>
      val emptyData = InputBlockTransactionsData(inputBlockId, Seq.empty)
      val bytes = inputBlockTransactionsMessageSpec.toBytes(emptyData)
      val recovered = inputBlockTransactionsMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual emptyData.inputBlockId
      recovered.transactions shouldEqual emptyData.transactions
    }
  }

  property("InputBlockTransactionsRequest serialization roundtrip") {
    forAll(inputBlockTransactionsRequestGen) { request =>
      val bytes = inputBlockTransactionsRequestMessageSpec.toBytes(request)
      val recovered = inputBlockTransactionsRequestMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual request.inputBlockId
      recovered.txIds.map(_.toSeq) shouldEqual request.txIds.map(_.toSeq)
    }
  }

  property("InputBlockTransactionsRequest serialization with empty tx ids") {
    forAll(modifierIdGen) { inputBlockId =>
      val emptyRequest = InputBlockTransactionsRequest(inputBlockId, Seq.empty)
      val bytes = inputBlockTransactionsRequestMessageSpec.toBytes(emptyRequest)
      val recovered = inputBlockTransactionsRequestMessageSpec.parseBytes(bytes)

      recovered.inputBlockId shouldEqual emptyRequest.inputBlockId
      recovered.txIds shouldEqual emptyRequest.txIds
    }
  }
}
