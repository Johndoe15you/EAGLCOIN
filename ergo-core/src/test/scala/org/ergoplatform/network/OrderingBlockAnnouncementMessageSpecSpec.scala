package org.ergoplatform.network

import org.ergoplatform.modifiers.history.extension.Extension
import org.ergoplatform.modifiers.mempool.ErgoTransaction
import org.ergoplatform.network.message.inputblocks.{OrderingBlockAnnouncement, OrderingBlockAnnouncementMessageSpec}
import org.ergoplatform.utils.{ErgoCorePropertyTest, SerializationTests}
import org.scalacheck.Gen

class OrderingBlockAnnouncementMessageSpecSpec extends ErgoCorePropertyTest with SerializationTests {
  import org.ergoplatform.utils.generators.CoreObjectGenerators._
  import org.ergoplatform.utils.generators.ErgoCoreGenerators._
  import org.ergoplatform.utils.generators.ErgoCoreTransactionGenerators._

  private val messageSpec = OrderingBlockAnnouncementMessageSpec

  private def orderingBlockAnnouncementGen: Gen[OrderingBlockAnnouncement] = for {
    header <- defaultHeaderGen
    nonBroadcastedTransactions <- Gen.listOf(invalidErgoTransactionGen).map(_.take(5))
    broadcastedTransactionIds <- Gen.listOf(modifierIdGen).map(_.take(5))
    extensionFields <- Gen.listOf(extensionKvGen(Extension.FieldKeySize, Extension.FieldValueMaxSize)).map(_.take(5).toStream)
  } yield OrderingBlockAnnouncement(
    header,
    nonBroadcastedTransactions,
    broadcastedTransactionIds,
    extensionFields
  )

  property("OrderingBlockAnnouncement serialization roundtrip") {
    forAll(orderingBlockAnnouncementGen) { announcement =>
      val bytes = messageSpec.toBytes(announcement)
      val recovered = messageSpec.parseBytes(bytes)

      // Verify individual components
      recovered.header shouldEqual announcement.header
      recovered.nonBroadcastedTransactions shouldEqual announcement.nonBroadcastedTransactions
      recovered.broadcastedTransactionIds shouldEqual announcement.broadcastedTransactionIds
      recovered.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) } shouldEqual 
        announcement.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) }

      // Verify the entire object
      recovered.header shouldEqual announcement.header
      recovered.nonBroadcastedTransactions shouldEqual announcement.nonBroadcastedTransactions
      recovered.broadcastedTransactionIds shouldEqual announcement.broadcastedTransactionIds
      recovered.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) } shouldEqual 
        announcement.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) }
    }
  }

  property("OrderingBlockAnnouncement serialization with empty collections") {
    forAll(defaultHeaderGen) { header =>
      val emptyAnnouncement = OrderingBlockAnnouncement(
        header,
        Seq.empty[ErgoTransaction],
        Seq.empty,
        Seq.empty
      )

      val bytes = messageSpec.toBytes(emptyAnnouncement)
      val recovered = messageSpec.parseBytes(bytes)

      recovered.header shouldEqual emptyAnnouncement.header
      recovered.nonBroadcastedTransactions shouldEqual emptyAnnouncement.nonBroadcastedTransactions
      recovered.broadcastedTransactionIds shouldEqual emptyAnnouncement.broadcastedTransactionIds
      recovered.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) } shouldEqual 
        emptyAnnouncement.extensionFields.toSeq.map { case (k, v) => (k.toSeq, v.toSeq) }
    }
  }
}
