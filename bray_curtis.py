import tensorflow as tf

class BrayCurtis(tf.keras.losses.Loss):
    """Class for calculating the Bray-Curtis dissimilarity with the Keras API."""

    def call(self, y_true, y_pred):
        # Find the elementwise minimum of pairs of samples
        #  and calculate the sum of the minimums in each sample.
        C_ij = tf.keras.backend.minimum(y_pred, y_true)
        C_ij = tf.keras.backend.sum(C_ij, axis=1)

        # Calculate the sum of each sample.
        S_i = tf.keras.backend.sum(y_true, axis=1)
        S_j = tf.keras.backend.sum(y_pred, axis=1)

        # Calculate and return Bray-Curtis dissimilarity.
        return 1 - ((2*C_ij) / (S_i+S_j))


if __name__ == '__main__':
    batch1 = tf.constant([[2.0, 2.0, 7.0], [5.0, 2.0, 2.0], [1.0, 2.0, 2.0]])
    batch2 = tf.constant([[2.0, 5.0, 2.0], [3.0, 3.0, 5.0], [2.0, 2.0, 1.0]])
    bray_curtis = BrayCurtis()
    result = bray_curtis.call(batch1, batch2)
    print(result)
