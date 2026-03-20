# SPDX-FileCopyrightText: Copyright (c) 2025 Advanced Micro Devices, Inc. All rights reserved.
# SPDX-FileCopyrightText: Copyright (c) 2025 Timor Knudsen (AMD)

# SPDX-License-Identifier: MIT

from os import listdir
from os.path import isfile, join

import cv2 as cv2
import numpy as np


def gto_simple(img: np.ndarray):
    logimg = np.log(img)
    return (logimg - np.min(logimg)) / (np.max(logimg) - np.min(logimg)) * 255


def gto_kimkautz(img: np.ndarray, c1: float = 3.0, c2: float = 1.0):
    img.shape[0]
    w = img.shape[1]

    logimg = np.log(img)  # once per pixel (current + previous frame)
    logmean = np.mean(logimg)  # once per pixel (previous frame)
    logmax = np.max(logimg)  # once per pixel (previous frame)
    logmin = np.min(logimg)  # once per pixel (previous frame)
    log_range = logmax - logmin  # once per frame

    # sigma2 = np.square((log_range) / c1)                        # once per frame

    d0 = logmax - logmin
    # d0 = np.log10(np.max(img)) - np.log10(np.min(img))
    # d0 = np.log10(np.max(img) - np.min(img))
    sigma = d0 / c1

    w = np.exp(-0.5 * np.square(logimg - logmean) / np.square(sigma))  # once per pixel

    # k1 = (np.log(256.0)) / (log_range)                        # once per frame
    # k1 = (np.log(256.0)) / (np.log(imgmax-imgmin))                        # once per frame
    maxLd = np.log(255)
    minLd = np.log(1)
    k1 = (maxLd - minLd) / (logmax - 0)
    # k1 = 0.43

    k2 = (1 - k1) * w + k1  # once per pixel

    L1 = np.exp(c2 * k2 * (logimg - logmean) + logmean)  # once per pixel
    # L1 = np.exp(k1 * logimg)

    print("  log_range  :", log_range)
    print("  logmax     :", logmax)
    print("  logmin     :", logmin)
    print("  logmean    :", logmean)
    print("  k1         :", k1)
    print("  np.max(k2) :", np.max(k2))
    print("  np.min(k2) :", np.min(k2))
    print("  c2         :", c2)
    print("  np.max(L1) :", np.max(L1))
    print("  np.min(L1) :", np.min(L1))

    return ((L1 - np.min(L1)) / (np.max(L1) - np.min(L1))) * 255


def gto_drago(Y: np.ndarray, b: float = 0.84):
    Y.shape[0]
    Y.shape[1]

    Y = Y - np.min(Y)
    L_av = np.mean(Y)  # once per frame
    L_max = np.max(Y) / L_av  # once per frame
    divider = np.log10(L_max + 1.0)  # once per frame

    L_w = Y / L_av  # per pixel - div or 1/x mult

    interpol = np.log(2.0 + np.sqrt(np.sqrt(L_w / L_max)) * 8.0)  # per pixel
    L_d = (np.log(L_w + 1.0)) / (divider * interpol)  # per pixel

    # img_div = img/np.mean(img)
    # b = 2 + 8*np.sqrt(np.sqrt(img_div))
    # L1 = np.log(img + 1) / (np.log10(img_div/max + 1) * np.log(b))

    # print('max(img_div)=', np.max(img_div))
    # print('min(img_div)=', np.min(img_div))

    return L_d * 255


def char_img(Y: np.ndarray):
    logY = np.log(Y)
    logAv = np.mean(logY)
    logMax = np.max(logY)
    logMin = np.min(logY)

    # logAvScaled = ((logAv - logMin) / (logMax - logMin)) * 255
    logAvScaled = ((logY - logAv) / (logMax - logMin)) * 128 + 127
    Ys = (logY - logMin) / (logMax - logMin) * 255

    return Ys, logAvScaled


if __name__ == "__main__":
    print("Start")

    files = [f for f in listdir("../dataset") if isfile(join("../dataset", f))]

    ci_simple = np.zeros((256, 256))
    ci_count = np.zeros((256, 256))

    for file in files:
        print("Processing", join("../dataset", file))
        cfa: np.ndarray | None = cv2.imread(
            join("../dataset", file), cv2.IMREAD_UNCHANGED
        )
        if cfa is None:
            continue
        rgb = cv2.cvtColor(cfa.astype(np.uint16), cv2.COLOR_BayerBG2BGR)
        xyz = cv2.cvtColor(rgb, cv2.COLOR_BGR2XYZ)
        L0 = xyz[:, :, 1]
        # L1 = gto_drago(L0)
        # L1 = gto_kimkautz(L0)
        L1 = gto_simple(L0)

        char_image, avg = char_img(L0)
        h = char_image.shape[0]
        w = char_image.shape[1]

        for y in range(0, h):
            for x in range(0, w):
                ci_simple[int(char_image[y, x]), int(avg[y, x])] += L1[y, x]
                ci_count[int(char_image[y, x]), int(avg[y, x])] += 1

    ci_simple /= ci_count
    cv2.imwrite("ci_simple_y-avg.png", ci_simple.astype(np.uint8))
